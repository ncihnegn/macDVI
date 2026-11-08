import AppKit

enum DocumentAutoScaleMode: Equatable {
    case none
    case width
    case height
}

final class DVIDocumentView: NSView {
    var document: DVIDocument? {
        didSet {
            fontCache.removeAll()
            pageRenderCache.removeAllObjects()
            pageRectsCache.removeAll()
            searchMatches.removeAll()
            activeSearchMatchIndex = -1
            if let document {
                type1FontProvider = Type1FontProvider(documentURL: document.url)
                pkFontProvider = PKFontProvider(documentURL: document.url)
                gfFontProvider = GFFontProvider(documentURL: document.url)
            } else {
                type1FontProvider = nil
                pkFontProvider = nil
                gfFontProvider = nil
            }
            updateFrameSize()
            needsDisplay = true
        }
    }

    var zoom: CGFloat = 1.0 {
        didSet {
            zoom = min(max(zoom, 0.25), 5.0)
            fontCache.removeAll()
            pageRenderCache.removeAllObjects()
            pageRectsCache.removeAll()
            updateFrameSize()
            needsDisplay = true
        }
    }

    var isTwoPageView: Bool = false {
        didSet {
            guard oldValue != isTwoPageView else { return }
            pageRectsCache.removeAll()
            updateFrameSize()
            needsDisplay = true
        }
    }

    typealias AutoScaleMode = DocumentAutoScaleMode

    var autoScaleMode: AutoScaleMode = .none {
        didSet {
            guard autoScaleMode != .none else { return }
            switch autoScaleMode {
            case .width:
                applyZoomToFitWidth()
            case .height:
                applyZoomToFitHeight()
            case .none:
                break
            }
        }
    }

    var autoScales: Bool {
        get { autoScaleMode != .none }
        set {
            autoScaleMode = newValue ? .width : .none
        }
    }

    var searchMatches: [DVISearchMatch] = [] {
        didSet {
            needsDisplay = true
        }
    }

    var activeSearchMatchIndex: Int = -1 {
        didSet {
            needsDisplay = true
        }
    }

    var synctexHighlightRect: CGRect? {
        didSet { needsDisplay = true }
    }
    var synctexHighlightPageIndex: Int? {
        didSet { needsDisplay = true }
    }
    private var synctexHighlightTimer: Timer?
    var onCommandClick: ((Int, CGPoint) -> Void)?

    override var isFlipped: Bool {
        true
    }

    private let pageGap: CGFloat = 28
    private let pageInset: CGFloat = 36
    private var fontCache: [FontCacheKey: NSFont] = [:]
    private let pageRenderCache = NSCache<NSString, NSImage>()
    private var pageRectsCache: [NSRect] = []
    private var type1FontProvider: Type1FontProvider?
    private var pkFontProvider: PKFontProvider?
    private var gfFontProvider: GFFontProvider?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        updateFrameSize()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        guard let document else { return }
        ensurePageRectsCached()

        for (index, page) in document.pages.enumerated() {
            let pageRect = rectForPage(at: index, page: page)
            if isTwoPageView {
                if index % 2 == 1 || index == document.pages.count - 1 {
                    if pageRect.minY > dirtyRect.maxY { break }
                }
            } else {
                if pageRect.minY > dirtyRect.maxY { break }
            }
            guard pageRect.intersects(dirtyRect) else { continue }
            drawPageBackground(in: pageRect)
            let img = pageImage(at: index, page: page, in: pageRect, document: document)
            img.draw(in: pageRect)
            drawSearchHighlights(for: index, in: pageRect)
            drawSyncTeXHighlight(for: index, in: pageRect)
        }
    }

    func pageImage(at index: Int, page: DVIPage, in pageRect: NSRect, document: DVIDocument) -> NSImage {
        let cacheKey = "\(document.url.path):\(index):\(Int(zoom * 1000))" as NSString
        if let cached = pageRenderCache.object(forKey: cacheKey) {
            return cached
        }

        let image = NSImage(size: pageRect.size, flipped: true) { [weak self] bounds in
            guard let self else { return false }
            NSColor.white.setFill()
            bounds.fill()
            self.draw(page: page, in: bounds, document: document)
            return true
        }

        pageRenderCache.setObject(image, forKey: cacheKey)
        return image
    }

    private func drawSearchHighlights(for pageIndex: Int, in pageRect: NSRect) {
        guard !searchMatches.isEmpty else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        for (matchIdx, match) in searchMatches.enumerated() {
            guard match.pageIndex == pageIndex else { continue }
            let isActive = (matchIdx == activeSearchMatchIndex)

            for rect in match.rects {
                let drawRect = CGRect(
                    x: pageRect.minX + CGFloat(rect.minX) * zoom,
                    y: pageRect.minY + CGFloat(rect.minY) * zoom,
                    width: CGFloat(rect.width) * zoom,
                    height: CGFloat(rect.height) * zoom
                )

                let path = CGPath(roundedRect: drawRect, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
                context.saveGState()
                context.addPath(path)

                if isActive {
                    context.setFillColor(NSColor.systemOrange.withAlphaComponent(0.60).cgColor)
                    context.fillPath()

                    context.addPath(path)
                    context.setStrokeColor(NSColor.systemOrange.cgColor)
                    context.setLineWidth(1.5)
                    context.strokePath()
                } else {
                    context.setFillColor(NSColor.systemYellow.withAlphaComponent(0.40).cgColor)
                    context.fillPath()
                }
                context.restoreGState()
            }
        }
    }

    func scrollToSearchMatch(_ match: DVISearchMatch) {
        guard let document, match.pageIndex >= 0, match.pageIndex < document.pages.count,
              let clipView = enclosingScrollView?.contentView else { return }
        ensurePageRectsCached()
        let pageRect = rectForPage(at: match.pageIndex, page: document.pages[match.pageIndex])

        guard let firstRect = match.rects.first else {
            scrollToPage(index: match.pageIndex)
            return
        }

        let unionRect = match.rects.reduce(firstRect) { $0.union($1) }
        let targetX = pageRect.minX + CGFloat(unionRect.minX) * zoom
        let targetY = pageRect.minY + CGFloat(unionRect.minY) * zoom
        let targetW = CGFloat(unionRect.width) * zoom
        let targetH = CGFloat(unionRect.height) * zoom

        let viewport = clipView.bounds
        let centerX = targetX + targetW / 2
        let centerY = targetY + targetH / 2

        var newX = centerX - viewport.width / 2
        var newY = centerY - viewport.height / 2

        let maxX = max(bounds.width - viewport.width, 0)
        let maxY = max(bounds.height - viewport.height, 0)
        newX = max(min(newX, maxX), 0)
        newY = max(min(newY, maxY), 0)

        clipView.scroll(to: NSPoint(x: newX, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    private func drawSyncTeXHighlight(for pageIndex: Int, in pageRect: NSRect) {
        guard let hRect = synctexHighlightRect, synctexHighlightPageIndex == pageIndex else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let drawRect = CGRect(
            x: pageRect.minX + CGFloat(hRect.minX) * zoom,
            y: pageRect.minY + CGFloat(hRect.minY) * zoom,
            width: CGFloat(hRect.width) * zoom,
            height: CGFloat(hRect.height) * zoom
        )
        let path = CGPath(roundedRect: drawRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        let color = AppSettings.shared.highlightColor.color
        context.saveGState()
        context.addPath(path)
        context.setFillColor(color.withAlphaComponent(0.35).cgColor)
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(color.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1.5)
        context.strokePath()
        context.restoreGState()
    }

    func showSyncTeXHighlight(pageIndex: Int, rect: CGRect) {
        synctexHighlightPageIndex = pageIndex
        synctexHighlightRect = rect
        synctexHighlightTimer?.invalidate()
        let duration = AppSettings.shared.highlightDuration
        synctexHighlightTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.synctexHighlightRect = nil
            self?.synctexHighlightPageIndex = nil
        }
        needsDisplay = true
    }

    func scrollToSyncTeX(pageIndex: Int, rect: CGRect) {
        guard let document, pageIndex >= 0, pageIndex < document.pages.count,
              let clipView = enclosingScrollView?.contentView else { return }
        ensurePageRectsCached()
        let pageRect = rectForPage(at: pageIndex, page: document.pages[pageIndex])

        let targetX = pageRect.minX + CGFloat(rect.minX) * zoom
        let targetY = pageRect.minY + CGFloat(rect.minY) * zoom
        let targetW = CGFloat(rect.width) * zoom
        let targetH = CGFloat(rect.height) * zoom

        let viewport = clipView.bounds
        let centerX = targetX + targetW / 2
        let centerY = targetY + targetH / 2

        var newX = centerX - viewport.width / 2
        var newY = centerY - viewport.height / 2

        let maxX = max(bounds.width - viewport.width, 0)
        let maxY = max(bounds.height - viewport.height, 0)
        newX = max(min(newX, maxX), 0)
        newY = max(min(newY, maxY), 0)

        clipView.scroll(to: NSPoint(x: newX, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        showSyncTeXHighlight(pageIndex: pageIndex, rect: rect)
    }

    private func drawPageBackground(in pageRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: NSColor.black.withAlphaComponent(0.15).cgColor)
        NSColor.white.setFill()
        NSBezierPath(rect: pageRect).fill()
        context.restoreGState()

        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: pageRect)
        border.lineWidth = 1 / max(window?.backingScaleFactor ?? 1, 1)
        border.stroke()
    }

    private func draw(page: DVIPage, in pageRect: NSRect, document: DVIDocument) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: pageRect)

        // Render inline PostScript items (such as TikZ / PGF / tcolorbox backgrounds) underneath text and rules
        let inlinePSItems = page.items.compactMap { item -> PostScriptInlineItem? in
            guard case .psInline(let ps) = item else { return nil }
            return ps
        }
        if !inlinePSItems.isEmpty && inlinePSItems.contains(where: { $0.hasVisualCommands }) {
            let scale = max(window?.backingScaleFactor ?? 2.0, 1.0)
            let pixelWidth = UInt32(max(pageRect.width * scale, 1))
            let pixelHeight = UInt32(max(pageRect.height * scale, 1))
            if let psImage = NativePostScriptRenderer.shared.renderInlinePostScript(
                documentHeaders: document.postScriptHeaders,
                inlineItems: inlinePSItems,
                pageWidth: pageRect.width,
                pageHeight: pageRect.height,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            ) {
                context.saveGState()
                context.translateBy(x: 0, y: pageRect.height)
                context.scaleBy(x: 1, y: -1)
                context.draw(psImage, in: CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height))
                context.restoreGState()
            }
        }

        for item in page.items {
            switch item {
            case .glyph(let glyph):
                draw(glyph: glyph, in: pageRect, document: document)
            case .nativeGlyphArray(let glyphArray):
                draw(nativeGlyphArray: glyphArray, in: pageRect, document: document)
            case .pic(let pic):
                draw(pic: pic, in: pageRect, document: document)
            case .postScriptPage(let psPage):
                draw(postScriptPage: psPage, in: pageRect, document: document)
            case .psGraphic(let psGraphic):
                draw(psGraphic: psGraphic, in: pageRect, document: document)
            case .psInline:
                continue
            case .rule(let rule):
                draw(rule: rule, in: pageRect)
            case .special:
                continue
            }
        }

        context.restoreGState()
    }

    private func draw(psGraphic: PostScriptGraphicItem, in pageRect: NSRect, document: DVIDocument) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        var fileURL: URL?
        if psGraphic.filePath.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: psGraphic.filePath)
        } else {
            let docDir = document.url.deletingLastPathComponent()
            let candidate = docDir.appendingPathComponent(psGraphic.filePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                fileURL = candidate
            } else if let found = TeXFileLocator.findFile(named: psGraphic.filePath) {
                fileURL = URL(fileURLWithPath: found)
            }
        }

        guard let resolvedURL = fileURL, FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return
        }

        let scale = max(window?.backingScaleFactor ?? 2.0, 1.0)
        let renderWidth = CGFloat(psGraphic.targetWidth) * zoom
        let renderHeight = CGFloat(psGraphic.targetHeight) * zoom
        let pixelWidth = UInt32(max(renderWidth * scale * 2.0, 100))
        let pixelHeight = UInt32(max(renderHeight * scale * 2.0, 100))

        let graphicX = pageRect.minX + CGFloat(psGraphic.x + psGraphic.hoffset) * zoom
        let graphicY = pageRect.minY + CGFloat(psGraphic.y + psGraphic.voffset) * zoom - renderHeight
        let graphicRect = CGRect(
            x: graphicX,
            y: graphicY,
            width: renderWidth,
            height: renderHeight
        )

        context.saveGState()
        defer { context.restoreGState() }
        if psGraphic.clip {
            context.clip(to: graphicRect)
        }
        context.translateBy(x: graphicRect.minX, y: graphicRect.maxY)
        context.scaleBy(x: 1, y: -1)

        let ext = resolvedURL.pathExtension.lowercased()
        let isPostScript = NativePostScriptRenderer.isPostScript(url: resolvedURL)
        if ext == "pdf",
           let pdfDoc = CGPDFDocument(resolvedURL as CFURL),
           let pdfPage = pdfDoc.page(at: 1) {
            let box = pdfPage.getBoxRect(.mediaBox)
            guard box.width > 0, box.height > 0 else { return }
            context.saveGState()
            context.scaleBy(
                x: graphicRect.width / box.width,
                y: graphicRect.height / box.height
            )
            context.drawPDFPage(pdfPage)
            context.restoreGState()
        } else if isPostScript,
                  let cgImage = NativePostScriptRenderer.shared.renderPage(
                      url: resolvedURL,
                      pageIndex: 0,
                      pixelWidth: pixelWidth,
                      pixelHeight: pixelHeight,
                      boundingBox: CGRect(
                          x: psGraphic.llx,
                          y: psGraphic.lly,
                          width: max(psGraphic.urx - psGraphic.llx, 1),
                          height: max(psGraphic.ury - psGraphic.lly, 1)
                      )
                  ) {
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: graphicRect.width, height: graphicRect.height)
            )
        } else if let image = NSImage(contentsOf: resolvedURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: graphicRect.width, height: graphicRect.height)
            )
        }
    }

    private func draw(postScriptPage: PostScriptPageItem, in pageRect: NSRect, document: DVIDocument) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = max(window?.backingScaleFactor ?? 2.0, 1.0)
        let pixelWidth = UInt32(max(pageRect.width * scale, 1))
        let pixelHeight = UInt32(max(pageRect.height * scale, 1))

        if let cgImage = NativePostScriptRenderer.shared.renderPage(
            url: postScriptPage.postScriptURL,
            pageIndex: postScriptPage.pageIndex,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        ) {
            context.saveGState()
            context.translateBy(x: pageRect.minX, y: pageRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pageRect.width, height: pageRect.height))
            context.restoreGState()
        }
    }

    private func draw(pic: XDVPicItem, in pageRect: NSRect, document: DVIDocument) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        var fileURL: URL?
        if pic.path.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: pic.path)
        } else {
            let docDir = document.url.deletingLastPathComponent()
            let candidate = docDir.appendingPathComponent(pic.path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                fileURL = candidate
            } else if let found = TeXFileLocator.findFile(named: pic.path) {
                fileURL = URL(fileURLWithPath: found)
            }
        }

        guard let resolvedURL = fileURL, FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return
        }

        let ext = resolvedURL.pathExtension.lowercased()
        let isPostScript = NativePostScriptRenderer.isPostScript(url: resolvedURL)
        let x = pageRect.minX + CGFloat(pic.x) * zoom
        let y = pageRect.minY + CGFloat(pic.y) * zoom

        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: x, y: y)

        if pic.transform.count == 6 {
            let t = pic.transform
            let matrix = CGAffineTransform(
                a: CGFloat(t[0]) * zoom,
                b: CGFloat(t[1]) * zoom,
                c: CGFloat(t[2]) * zoom,
                d: CGFloat(t[3]) * zoom,
                tx: CGFloat(t[4]) * zoom,
                ty: CGFloat(t[5]) * zoom
            )
            context.concatenate(matrix)
        }

        if ext == "pdf", let pdfDoc = CGPDFDocument(resolvedURL as CFURL), let pdfPage = pdfDoc.page(at: max(pic.pageNumber, 1)) {
            let box = pdfPage.getBoxRect(.mediaBox)
            context.saveGState()
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -box.height)
            context.drawPDFPage(pdfPage)
            context.restoreGState()
        } else if isPostScript,
                  let cgImage = NativePostScriptRenderer.shared.renderPage(
                      url: resolvedURL,
                      pageIndex: max(pic.pageNumber - 1, 0),
                      pixelWidth: 800,
                      pixelHeight: 800
                  ) {
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
            context.saveGState()
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -height)
            context.draw(cgImage, in: imageRect)
            context.restoreGState()
        } else if let image = NSImage(contentsOf: resolvedURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
            context.saveGState()
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -height)
            context.draw(cgImage, in: imageRect)
            context.restoreGState()
        }
    }

    private func draw(nativeGlyphArray: DVINativeGlyphArray, in pageRect: NSRect, document: DVIDocument) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let definition = document.fonts[nativeGlyphArray.fontNumber]
        let outlineFont = definition.flatMap { type1FontProvider?.font(for: $0) }

        let baseX = pageRect.minX + CGFloat(nativeGlyphArray.x) * zoom
        let baseY = pageRect.minY + CGFloat(nativeGlyphArray.baselineY) * zoom
        let fontSize = max(CGFloat(nativeGlyphArray.fontSize) * zoom, 1)

        let extend = CGFloat(definition?.nativeExtend ?? 1.0)
        let slant = CGFloat(definition?.nativeSlant ?? 0.0)

        context.saveGState()
        context.setFillColor(NSColor(dviColor: nativeGlyphArray.color).cgColor)

        for pos in nativeGlyphArray.glyphs {
            let gx = baseX + CGFloat(pos.x) * zoom
            let gy = baseY + CGFloat(pos.y) * zoom

            if let outlineFont, let path = outlineFont.path(forGlyphID: CGGlyph(pos.glyphID)) {
                let scale = max(fontSize / CGFloat(outlineFont.unitsPerEm), 0.001)
                context.saveGState()
                context.translateBy(x: gx, y: gy)
                var transform = CGAffineTransform.identity
                transform = transform.scaledBy(x: scale * extend, y: -scale)
                if slant != 0 {
                    transform = transform.concatenating(CGAffineTransform(1, 0, -slant, 1, 0, 0))
                }
                context.concatenate(transform)
                context.addPath(path)
                context.fillPath()
                context.restoreGState()
            }
        }

        context.restoreGState()
    }

    private func draw(glyph: DVIGlyph, in pageRect: NSRect, document: DVIDocument) {
        let definition = document.fonts[glyph.fontNumber]
        let texName = definition?.name ?? ""
        if let definition,
           let outlineFont = type1FontProvider?.font(for: definition),
           let glyphPath = outlinePath(for: glyph, font: outlineFont, texName: texName) {
            draw(type1Path: glyphPath, font: outlineFont, glyph: glyph, in: pageRect)
            return
        }

        if let definition,
           let pkFont = pkFontProvider?.font(for: definition),
           let pkGlyph = pkFont.glyphs[glyph.characterCode],
           drawPKGlyph(pkGlyph, font: pkFont, definition: definition, glyph: glyph, in: pageRect) {
            return
        }

        if let definition,
           let gfFont = gfFontProvider?.font(for: definition),
           let gfGlyph = gfFont.glyphs[glyph.characterCode],
           drawGFGlyph(gfGlyph, font: gfFont, definition: definition, glyph: glyph, in: pageRect) {
            return
        }

        let font = renderFont(for: definition, glyph: glyph)
        let text = TeXGlyphMapper.string(for: glyph.characterCode, fontName: texName)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(dviColor: glyph.color)
        ]

        let x = pageRect.minX + CGFloat(glyph.x) * zoom
        let baseline = pageRect.minY + CGFloat(glyph.baselineY) * zoom
        let y = baseline - font.ascender
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    private func drawPKGlyph(
        _ pkGlyph: PKGlyph,
        font: PKFont,
        definition: DVIFontDefinition,
        glyph: DVIGlyph,
        in pageRect: NSRect
    ) -> Bool {
        guard pkGlyph.width > 0, pkGlyph.height > 0,
              let provider = pkFontProvider,
              let mask = provider.maskImage(for: pkGlyph, fontKey: definition.texName.lowercased()),
              let context = NSGraphicsContext.current?.cgContext else {
            return false
        }

        let pointsPerPixel = font.pointsPerPixel
        let scale = CGFloat(pointsPerPixel) * zoom
        let x = pageRect.minX + CGFloat(glyph.x) * zoom - CGFloat(pkGlyph.hoff) * scale
        let baseline = pageRect.minY + CGFloat(glyph.baselineY) * zoom
        let top = baseline - CGFloat(pkGlyph.voff) * scale
        let drawRect = CGRect(
            x: x,
            y: top,
            width: CGFloat(pkGlyph.width) * scale,
            height: CGFloat(pkGlyph.height) * scale
        )

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: drawRect.minX, y: drawRect.maxY)
        context.scaleBy(x: 1, y: -1)
        let local = CGRect(x: 0, y: 0, width: drawRect.width, height: drawRect.height)
        context.clip(to: local, mask: mask)
        context.setFillColor(NSColor(dviColor: glyph.color).cgColor)
        context.fill(local)
        return true
    }

    private func drawGFGlyph(
        _ gfGlyph: GFGlyph,
        font: GFFont,
        definition: DVIFontDefinition,
        glyph: DVIGlyph,
        in pageRect: NSRect
    ) -> Bool {
        guard gfGlyph.width > 0, gfGlyph.height > 0,
              let provider = gfFontProvider,
              let mask = provider.maskImage(for: gfGlyph, fontKey: definition.texName.lowercased()),
              let context = NSGraphicsContext.current?.cgContext else {
            return false
        }

        let pointsPerPixel = font.pointsPerPixel
        let scale = CGFloat(pointsPerPixel) * zoom
        let x = pageRect.minX + CGFloat(glyph.x) * zoom - CGFloat(gfGlyph.hoff) * scale
        let baseline = pageRect.minY + CGFloat(glyph.baselineY) * zoom
        let top = baseline - CGFloat(gfGlyph.voff) * scale
        let drawRect = CGRect(
            x: x,
            y: top,
            width: CGFloat(gfGlyph.width) * scale,
            height: CGFloat(gfGlyph.height) * scale
        )

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: drawRect.minX, y: drawRect.maxY)
        context.scaleBy(x: 1, y: -1)
        let local = CGRect(x: 0, y: 0, width: drawRect.width, height: drawRect.height)
        context.clip(to: local, mask: mask)
        context.setFillColor(NSColor(dviColor: glyph.color).cgColor)
        context.fill(local)
        return true
    }

    private func outlinePath(for glyph: DVIGlyph, font: OutlineFont, texName: String) -> CGPath? {
        let glyphName = TeXGlyphMapper.glyphName(for: glyph.characterCode, fontName: texName)
        if font.kind == .type1, let glyphName, let path = font.path(forGlyphNamed: glyphName) {
            return path
        }
        let mapped = TeXGlyphMapper.string(for: glyph.characterCode, fontName: texName)
        if let scalar = mapped.unicodeScalars.first, let path = font.path(forUnicode: scalar.value) {
            return path
        }
        if let glyphName, let path = font.path(forGlyphNamed: glyphName) {
            return path
        }
        if let scalar = UnicodeScalar(glyph.characterCode), let path = font.path(forUnicode: scalar.value) {
            return path
        }
        return nil
    }

    private func draw(type1Path: CGPath, font: Type1Font, glyph: DVIGlyph, in pageRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let x = pageRect.minX + CGFloat(glyph.x) * zoom
        let baseline = pageRect.minY + CGFloat(glyph.baselineY) * zoom
        let scale = max(CGFloat(glyph.fontSize) * zoom / CGFloat(font.unitsPerEm), 0.001)

        context.saveGState()
        context.translateBy(x: x, y: baseline)
        context.scaleBy(x: scale, y: -scale)
        context.addPath(type1Path)
        context.setFillColor(NSColor(dviColor: glyph.color).cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private func draw(rule: DVIRule, in pageRect: NSRect) {
        NSColor(dviColor: rule.color).setFill()
        let rect = NSRect(
            x: pageRect.minX + CGFloat(rule.x) * zoom,
            y: pageRect.minY + CGFloat(rule.y) * zoom,
            width: max(CGFloat(rule.width) * zoom, 0.5),
            height: max(CGFloat(rule.height) * zoom, 0.5)
        )
        rect.fill()
    }

    private func renderFont(for definition: DVIFontDefinition?, glyph: DVIGlyph) -> NSFont {
        let texName = definition?.name.lowercased() ?? ""
        let size = max(CGFloat(glyph.fontSize) * zoom, 1)
        let key = FontCacheKey(fontNumber: glyph.fontNumber, pointSize: Int((size * 10).rounded()))
        if let cached = fontCache[key] {
            return cached
        }

        let font: NSFont
        if texName.contains("tt") {
            font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        } else if texName.hasPrefix("cmsy") || texName.hasPrefix("cmex") || texName.hasPrefix("msam") || texName.hasPrefix("msbm") {
            font = NSFont(name: "Symbol", size: size) ?? NSFont.systemFont(ofSize: size)
        } else {
            var base = NSFont(name: "Times New Roman", size: size)
                ?? NSFont(name: "Times", size: size)
                ?? NSFont.systemFont(ofSize: size)
            let manager = NSFontManager.shared
            if texName.contains("bx") || texName.contains("bold") || texName.contains("cmb") {
                base = manager.convert(base, toHaveTrait: .boldFontMask)
            }
            if texName.contains("ti") || texName.contains("sl") || texName.hasPrefix("cmmi") {
                base = manager.convert(base, toHaveTrait: .italicFontMask)
            }
            font = base
        }

        fontCache[key] = font
        return font
    }

    private var isApplyingZoomToFit = false

    func applyZoomToFit() {
        applyZoomToFitWidth()
    }

    func applyZoomToFitWidth() {
        guard !isApplyingZoomToFit else { return }
        guard let document, !document.pages.isEmpty else { return }
        let clipWidth = enclosingScrollView?.contentSize.width ?? enclosingScrollView?.contentView.bounds.width ?? bounds.width
        let availableWidth = max(clipWidth - pageInset * 2, 100)

        let targetPage = document.pages[min(currentPageIndex, document.pages.count - 1)]
        let pageWidth: CGFloat

        if isTwoPageView {
            let leftW = CGFloat(targetPage.mediaBox.width)
            let nextIdx = (currentPageIndex - (currentPageIndex % 2)) + 1
            if nextIdx < document.pages.count {
                let rightPage = document.pages[nextIdx]
                let rightW = CGFloat(rightPage.mediaBox.width)
                pageWidth = leftW + rightW + pageGap
            } else {
                pageWidth = leftW
            }
        } else {
            pageWidth = CGFloat(targetPage.mediaBox.width)
        }

        guard pageWidth > 0 else { return }
        let targetZoom = availableWidth / pageWidth
        let clampedZoom = min(max(targetZoom, 0.1), 8.0)

        if abs(zoom - clampedZoom) > 0.001 {
            isApplyingZoomToFit = true
            zoom = clampedZoom
            isApplyingZoomToFit = false
        }
    }

    func applyZoomToFitHeight() {
        guard !isApplyingZoomToFit else { return }
        guard let document, !document.pages.isEmpty else { return }
        let clipHeight = enclosingScrollView?.contentSize.height ?? enclosingScrollView?.contentView.bounds.height ?? bounds.height
        let availableHeight = max(clipHeight - 1.5 * pageGap, 100)

        let targetPage = document.pages[min(currentPageIndex, document.pages.count - 1)]
        let pageHeight: CGFloat

        if isTwoPageView {
            let leftH = CGFloat(targetPage.mediaBox.height)
            let nextIdx = (currentPageIndex - (currentPageIndex % 2)) + 1
            if nextIdx < document.pages.count {
                let rightPage = document.pages[nextIdx]
                let rightH = CGFloat(rightPage.mediaBox.height)
                pageHeight = max(leftH, rightH)
            } else {
                pageHeight = leftH
            }
        } else {
            pageHeight = CGFloat(targetPage.mediaBox.height)
        }

        guard pageHeight > 0 else { return }
        let targetZoom = availableHeight / pageHeight
        let clampedZoom = min(max(targetZoom, 0.1), 8.0)

        if abs(zoom - clampedZoom) > 0.001 {
            isApplyingZoomToFit = true
            zoom = clampedZoom
            isApplyingZoomToFit = false
        }
    }

    private func updateFrameSize() {
        let clipWidth = enclosingScrollView?.contentSize.width ?? enclosingScrollView?.contentView.bounds.width ?? 900
        guard let document, !document.pages.isEmpty else {
            setFrameSize(CGSize(width: max(clipWidth, 900), height: 600))
            return
        }

        switch autoScaleMode {
        case .width:
            applyZoomToFitWidth()
        case .height:
            applyZoomToFitHeight()
        case .none:
            break
        }

        ensurePageRectsCached()
        let maxPageWidth: CGFloat
        let totalContentHeight: CGFloat

        if isTwoPageView {
            var maxRowWidth: CGFloat = 0
            var totalHeight: CGFloat = pageInset
            let count = document.pages.count
            var i = 0
            while i < count {
                let w1 = CGFloat(document.pages[i].mediaBox.width) * zoom
                let h1 = CGFloat(document.pages[i].mediaBox.height) * zoom
                if i + 1 < count {
                    let w2 = CGFloat(document.pages[i + 1].mediaBox.width) * zoom
                    let h2 = CGFloat(document.pages[i + 1].mediaBox.height) * zoom
                    let rowW = w1 + pageGap + w2
                    maxRowWidth = max(maxRowWidth, rowW)
                    totalHeight += max(h1, h2) + pageGap
                    i += 2
                } else {
                    maxRowWidth = max(maxRowWidth, w1)
                    totalHeight += h1 + pageGap
                    i += 1
                }
            }
            maxPageWidth = maxRowWidth
            totalContentHeight = totalHeight - pageGap + pageInset
        } else {
            maxPageWidth = pageRectsCache.map { $0.width }.max() ?? 612
            let totalPageHeight = document.pages
                .map { CGFloat($0.mediaBox.height) * zoom }
                .reduce(0, +)
            let totalGap = pageGap * CGFloat(max(document.pages.count - 1, 0))
            totalContentHeight = totalPageHeight + totalGap + pageInset * 2
        }

        let targetSize = CGSize(
            width: max(clipWidth, maxPageWidth + pageInset * 2),
            height: max(totalContentHeight, 600)
        )

        if abs(frame.width - targetSize.width) > 0.5 || abs(frame.height - targetSize.height) > 0.5 {
            setFrameSize(targetSize)
            pageRectsCache.removeAll()
            ensurePageRectsCached()
        }
    }

    private func ensurePageRectsCached() {
        guard let document else {
            pageRectsCache.removeAll()
            return
        }
        if pageRectsCache.count == document.pages.count {
            return
        }
        var rects: [NSRect] = []
        rects.reserveCapacity(document.pages.count)

        if isTwoPageView {
            let count = document.pages.count
            var rowDimensions: [(width: CGFloat, height: CGFloat, leftW: CGFloat, leftH: CGFloat, rightW: CGFloat, rightH: CGFloat)] = []
            var maxRowWidth: CGFloat = 0
            var i = 0
            while i < count {
                let leftPage = document.pages[i]
                let w1 = CGFloat(leftPage.mediaBox.width) * zoom
                let h1 = CGFloat(leftPage.mediaBox.height) * zoom
                if i + 1 < count {
                    let rightPage = document.pages[i + 1]
                    let w2 = CGFloat(rightPage.mediaBox.width) * zoom
                    let h2 = CGFloat(rightPage.mediaBox.height) * zoom
                    let rowW = w1 + pageGap + w2
                    let rowH = max(h1, h2)
                    maxRowWidth = max(maxRowWidth, rowW)
                    rowDimensions.append((rowW, rowH, w1, h1, w2, h2))
                    i += 2
                } else {
                    let rowW = w1
                    let rowH = h1
                    maxRowWidth = max(maxRowWidth, rowW)
                    rowDimensions.append((rowW, rowH, w1, h1, 0, 0))
                    i += 1
                }
            }

            var y = pageInset
            for row in rowDimensions {
                if row.rightW > 0 {
                    let rowStartX = max((bounds.width - row.width) / 2, pageInset)
                    let leftY = y + (row.height - row.leftH) / 2
                    let rightY = y + (row.height - row.rightH) / 2
                    rects.append(NSRect(x: rowStartX, y: leftY, width: row.leftW, height: row.leftH))
                    rects.append(NSRect(x: rowStartX + row.leftW + pageGap, y: rightY, width: row.rightW, height: row.rightH))
                } else {
                    let rowStartX: CGFloat
                    if count > 1 {
                        rowStartX = max((bounds.width - maxRowWidth) / 2, pageInset)
                    } else {
                        rowStartX = max((bounds.width - row.width) / 2, pageInset)
                    }
                    rects.append(NSRect(x: rowStartX, y: y, width: row.leftW, height: row.leftH))
                }
                y += row.height + pageGap
            }
        } else {
            var y = pageInset
            for page in document.pages {
                let width = CGFloat(page.mediaBox.width) * zoom
                let height = CGFloat(page.mediaBox.height) * zoom
                let x = max((bounds.width - width) / 2, pageInset)
                rects.append(NSRect(x: x, y: y, width: width, height: height))
                y += height + pageGap
            }
        }
        pageRectsCache = rects
    }

    func rectForPage(at index: Int, page: DVIPage) -> NSRect {
        if index < pageRectsCache.count {
            return pageRectsCache[index]
        }
        ensurePageRectsCached()
        if index < pageRectsCache.count {
            return pageRectsCache[index]
        }
        let width = CGFloat(page.mediaBox.width) * zoom
        let height = CGFloat(page.mediaBox.height) * zoom
        let x = max((bounds.width - width) / 2, pageInset)
        return NSRect(x: x, y: pageInset, width: width, height: height)
    }

    // MARK: - Responder & Keyboard / Navigation

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.modifierFlags.contains(.command) {
            let clickPoint = convert(event.locationInWindow, from: nil)
            ensurePageRectsCached()
            if let document {
                for (index, page) in document.pages.enumerated() {
                    let pageRect = rectForPage(at: index, page: page)
                    if pageRect.contains(clickPoint) {
                        let pageX = (clickPoint.x - pageRect.minX) / zoom
                        let pageY = (clickPoint.y - pageRect.minY) / zoom
                        onCommandClick?(index, CGPoint(x: pageX, y: pageY))
                        return
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        switch characters {
        case " ":
            if event.modifierFlags.contains(.shift) {
                scrollPageUp()
            } else {
                scrollPageDown()
            }
        case String(utf16CodeUnits: [unichar(NSPageDownFunctionKey)], count: 1):
            scrollPageDown()
        case String(utf16CodeUnits: [unichar(NSPageUpFunctionKey)], count: 1):
            scrollPageUp()
        case String(utf16CodeUnits: [unichar(NSDownArrowFunctionKey)], count: 1):
            if event.modifierFlags.contains(.command) {
                scrollToBottom()
            } else if event.modifierFlags.contains(.option) {
                goToNextPage()
            } else {
                scrollLineDown()
            }
        case String(utf16CodeUnits: [unichar(NSUpArrowFunctionKey)], count: 1):
            if event.modifierFlags.contains(.command) {
                scrollToTop()
            } else if event.modifierFlags.contains(.option) {
                goToPreviousPage()
            } else {
                scrollLineUp()
            }
        case String(utf16CodeUnits: [unichar(NSHomeFunctionKey)], count: 1):
            scrollToTop()
        case String(utf16CodeUnits: [unichar(NSEndFunctionKey)], count: 1):
            scrollToBottom()
        case "g", "G":
            if event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                NSApp.sendAction(#selector(DocumentWindowController.goToPage(_:)), to: nil, from: self)
            } else {
                interpretKeyEvents([event])
            }
        default:
            interpretKeyEvents([event])
        }
    }

    @objc override func pageDown(_ sender: Any?) {
        scrollPageDown()
    }

    @objc override func pageUp(_ sender: Any?) {
        scrollPageUp()
    }

    @objc override func scrollPageDown(_ sender: Any?) {
        scrollPageDown()
    }

    @objc override func scrollPageUp(_ sender: Any?) {
        scrollPageUp()
    }

    @objc override func moveDown(_ sender: Any?) {
        scrollLineDown()
    }

    @objc override func moveUp(_ sender: Any?) {
        scrollLineUp()
    }

    @objc override func scrollToBeginningOfDocument(_ sender: Any?) {
        scrollToTop()
    }

    @objc override func scrollToEndOfDocument(_ sender: Any?) {
        scrollToBottom()
    }

    @objc override func moveToBeginningOfDocument(_ sender: Any?) {
        scrollToTop()
    }

    @objc override func moveToEndOfDocument(_ sender: Any?) {
        scrollToBottom()
    }

    func scrollPageDown() {
        if autoScaleMode == .height {
            goToNextPage()
            return
        }
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let viewportHeight = clipView.bounds.height
        let scrollDelta = max(viewportHeight - 40, 50)
        let newY = min(currentOrigin.y + scrollDelta, max(bounds.height - viewportHeight, 0))
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    func scrollPageUp() {
        if autoScaleMode == .height {
            goToPreviousPage()
            return
        }
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let viewportHeight = clipView.bounds.height
        let scrollDelta = max(viewportHeight - 40, 50)
        let newY = max(currentOrigin.y - scrollDelta, 0)
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    func scrollLineDown() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let viewportHeight = clipView.bounds.height
        let newY = min(currentOrigin.y + 40, max(bounds.height - viewportHeight, 0))
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    func scrollLineUp() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let newY = max(currentOrigin.y - 40, 0)
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    func scrollToTop() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: 0))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    func scrollToBottom() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let viewportHeight = clipView.bounds.height
        let newY = max(bounds.height - viewportHeight, 0)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    func scrollToPage(index: Int) {
        guard let document, index >= 0, index < document.pages.count,
              let clipView = enclosingScrollView?.contentView else { return }
        let targetIndex = isTwoPageView ? (index - (index % 2)) : index
        let newY: CGFloat
        if targetIndex == 0 && autoScaleMode != .height {
            newY = 0
        } else {
            let pageRect = rectForPage(at: targetIndex, page: document.pages[targetIndex])
            newY = max(pageRect.minY - pageGap / 2, 0)
        }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }

    var currentPageIndex: Int {
        guard let document, !document.pages.isEmpty,
              let clipView = enclosingScrollView?.contentView else { return 0 }
        let midY = clipView.bounds.midY
        for (index, page) in document.pages.enumerated() {
            let rect = rectForPage(at: index, page: page)
            if midY >= rect.minY && midY <= rect.maxY {
                return isTwoPageView ? (index - (index % 2)) : index
            }
            if rect.minY > midY {
                let candidate = max(index - 1, 0)
                return isTwoPageView ? (candidate - (candidate % 2)) : candidate
            }
        }
        let last = document.pages.count - 1
        return isTwoPageView ? (last - (last % 2)) : last
    }

    func goToNextPage() {
        let step = isTwoPageView ? 2 : 1
        let current = isTwoPageView ? (currentPageIndex - (currentPageIndex % 2)) : currentPageIndex
        let next = min(current + step, (document?.pages.count ?? 1) - 1)
        scrollToPage(index: next)
    }

    func goToPreviousPage() {
        let step = isTwoPageView ? 2 : 1
        let current = isTwoPageView ? (currentPageIndex - (currentPageIndex % 2)) : currentPageIndex
        let prev = max(current - step, 0)
        scrollToPage(index: prev)
    }

    func currentScrollPosition() -> (pageIndex: Int, progress: CGFloat) {
        guard let document, !document.pages.isEmpty,
              let clipView = enclosingScrollView?.contentView else {
            return (0, 0)
        }
        let y = clipView.bounds.origin.y
        ensurePageRectsCached()
        let count = document.pages.count

        if isTwoPageView {
            var i = 0
            while i < count {
                let rect = rectForPage(at: i, page: document.pages[i])
                let nextRowIndex = i + 2
                let nextY = (nextRowIndex < count) ? rectForPage(at: nextRowIndex, page: document.pages[nextRowIndex]).minY : rect.maxY
                let rowSpan = max(nextY - rect.minY, rect.height)
                if y < nextY || nextRowIndex >= count {
                    let progress = max(min((y - rect.minY) / max(rowSpan, 1), 1.0), 0.0)
                    return (i, progress)
                }
                i += 2
            }
            return (count - 1, 0)
        } else {
            for i in 0..<count {
                let rect = rectForPage(at: i, page: document.pages[i])
                let nextY = (i + 1 < count) ? rectForPage(at: i + 1, page: document.pages[i + 1]).minY : rect.maxY
                let rowSpan = max(nextY - rect.minY, rect.height)
                if y < nextY || i == count - 1 {
                    let progress = max(min((y - rect.minY) / max(rowSpan, 1), 1.0), 0.0)
                    return (i, progress)
                }
            }
            return (count - 1, 0)
        }
    }

    func scrollToPosition(pageIndex: Int, progress: CGFloat) {
        guard let document, !document.pages.isEmpty,
              let clipView = enclosingScrollView?.contentView else { return }
        ensurePageRectsCached()
        let count = document.pages.count
        let clampedIndex = max(min(pageIndex, count - 1), 0)
        let baseIndex = isTwoPageView ? (clampedIndex / 2) * 2 : clampedIndex
        let rect = rectForPage(at: baseIndex, page: document.pages[baseIndex])
        let nextIndex = isTwoPageView ? baseIndex + 2 : baseIndex + 1
        let nextY = (nextIndex < count) ? rectForPage(at: nextIndex, page: document.pages[nextIndex]).minY : rect.maxY
        let rowSpan = max(nextY - rect.minY, rect.height)
        let targetY = rect.minY + progress * rowSpan
        let maxScrollY = max(bounds.height - clipView.bounds.height, 0)
        let clampedY = max(min(targetY, maxScrollY), 0)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: clampedY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
        needsDisplay = true
    }
}

private struct FontCacheKey: Hashable {
    let fontNumber: Int
    let pointSize: Int
}

private extension NSColor {
    convenience init(dviColor: DVIColor) {
        self.init(
            calibratedRed: CGFloat(dviColor.red),
            green: CGFloat(dviColor.green),
            blue: CGFloat(dviColor.blue),
            alpha: CGFloat(dviColor.alpha)
        )
    }
}
