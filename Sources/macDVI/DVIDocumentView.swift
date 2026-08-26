import AppKit

final class DVIDocumentView: NSView {
    var document: DVIDocument? {
        didSet {
            fontCache.removeAll()
            pageRenderCache.removeAllObjects()
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
            updateFrameSize()
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    private let pageGap: CGFloat = 28
    private let pageInset: CGFloat = 36
    private var fontCache: [FontCacheKey: NSFont] = [:]
    private let pageRenderCache = NSCache<NSString, NSImage>()
    private var type1FontProvider: Type1FontProvider?
    private var pkFontProvider: PKFontProvider?
    private var gfFontProvider: GFFontProvider?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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

        for (index, page) in document.pages.enumerated() {
            let pageRect = rectForPage(at: index, page: page)
            guard pageRect.intersects(dirtyRect) else { continue }
            drawPageBackground(in: pageRect)
            let img = pageImage(at: index, page: page, in: pageRect, document: document)
            img.draw(in: pageRect)
        }
    }

    private func pageImage(at index: Int, page: DVIPage, in pageRect: NSRect, document: DVIDocument) -> NSImage {
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

        if let cgImage = NativePostScriptRenderer.shared.renderPage(
            url: resolvedURL,
            pageIndex: 0,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        ) {
            let graphicX = pageRect.minX + CGFloat(psGraphic.x + psGraphic.hoffset) * zoom
            let graphicY = pageRect.minY + CGFloat(psGraphic.y + psGraphic.voffset) * zoom - renderHeight
            let graphicRect = CGRect(
                x: graphicX,
                y: graphicY,
                width: renderWidth,
                height: renderHeight
            )
            context.saveGState()
            if psGraphic.clip {
                context.clip(to: graphicRect)
            }
            context.translateBy(x: graphicRect.minX, y: graphicRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: graphicRect.width, height: graphicRect.height))
            context.restoreGState()
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
        } else if (ext == "ps" || ext == "eps"),
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

    private func updateFrameSize() {
        let clipWidth = enclosingScrollView?.contentView.bounds.width ?? 900
        guard let document, !document.pages.isEmpty else {
            setFrameSize(CGSize(width: max(clipWidth, 900), height: 600))
            return
        }

        let maxPageWidth = document.pages.map { CGFloat($0.mediaBox.width) * zoom }.max() ?? 612
        let totalPageHeight = document.pages
            .map { CGFloat($0.mediaBox.height) * zoom }
            .reduce(0, +)
        let totalGap = pageGap * CGFloat(max(document.pages.count - 1, 0))
        let targetSize = CGSize(
            width: max(clipWidth, maxPageWidth + pageInset * 2),
            height: totalPageHeight + totalGap + pageInset * 2
        )

        if abs(frame.width - targetSize.width) > 0.5 || abs(frame.height - targetSize.height) > 0.5 {
            setFrameSize(targetSize)
        }
    }

    private func rectForPage(at index: Int, page: DVIPage) -> NSRect {
        guard let document else { return .zero }
        var y = pageInset
        for previous in 0..<index {
            y += CGFloat(document.pages[previous].mediaBox.height) * zoom + pageGap
        }
        let width = CGFloat(page.mediaBox.width) * zoom
        let height = CGFloat(page.mediaBox.height) * zoom
        let x = max((bounds.width - width) / 2, pageInset)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Responder & Keyboard / Navigation

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
            if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
                goToNextPage()
            } else {
                scrollLineDown()
            }
        case String(utf16CodeUnits: [unichar(NSUpArrowFunctionKey)], count: 1):
            if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
                goToPreviousPage()
            } else {
                scrollLineUp()
            }
        case String(utf16CodeUnits: [unichar(NSHomeFunctionKey)], count: 1):
            scrollToTop()
        case String(utf16CodeUnits: [unichar(NSEndFunctionKey)], count: 1):
            scrollToBottom()
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

    func scrollPageDown() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let viewportHeight = clipView.bounds.height
        let scrollDelta = max(viewportHeight - 40, 50)
        let newY = min(currentOrigin.y + scrollDelta, max(bounds.height - viewportHeight, 0))
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func scrollPageUp() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let viewportHeight = clipView.bounds.height
        let scrollDelta = max(viewportHeight - 40, 50)
        let newY = max(currentOrigin.y - scrollDelta, 0)
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func scrollLineDown() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let viewportHeight = clipView.bounds.height
        let newY = min(currentOrigin.y + 40, max(bounds.height - viewportHeight, 0))
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func scrollLineUp() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let currentOrigin = clipView.bounds.origin
        let newY = max(currentOrigin.y - 40, 0)
        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func scrollToTop() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: 0))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func scrollToBottom() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let viewportHeight = clipView.bounds.height
        let newY = max(bounds.height - viewportHeight, 0)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func scrollToPage(index: Int) {
        guard let document, index >= 0, index < document.pages.count,
              let clipView = enclosingScrollView?.contentView else { return }
        let pageRect = rectForPage(at: index, page: document.pages[index])
        let newY = max(pageRect.minY - pageGap / 2, 0)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: newY))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    var currentPageIndex: Int {
        guard let document, !document.pages.isEmpty,
              let clipView = enclosingScrollView?.contentView else { return 0 }
        let midY = clipView.bounds.midY
        for (index, page) in document.pages.enumerated() {
            let rect = rectForPage(at: index, page: page)
            if midY >= rect.minY && midY <= rect.maxY {
                return index
            }
            if rect.minY > midY {
                return max(index - 1, 0)
            }
        }
        return document.pages.count - 1
    }

    func goToNextPage() {
        let next = min(currentPageIndex + 1, (document?.pages.count ?? 1) - 1)
        scrollToPage(index: next)
    }

    func goToPreviousPage() {
        let prev = max(currentPageIndex - 1, 0)
        scrollToPage(index: prev)
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
