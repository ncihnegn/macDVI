import AppKit

final class DVIDocumentView: NSView {
    var document: DVIDocument? {
        didSet {
            fontCache.removeAll()
            if let document {
                type1FontProvider = Type1FontProvider(documentURL: document.url)
            } else {
                type1FontProvider = nil
            }
            updateFrameSize()
            needsDisplay = true
        }
    }

    var zoom: CGFloat = 1.0 {
        didSet {
            zoom = min(max(zoom, 0.25), 5.0)
            fontCache.removeAll()
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
    private var type1FontProvider: Type1FontProvider?

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
            draw(page: page, in: pageRect, document: document)
        }
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
            case .rule(let rule):
                draw(rule: rule, in: pageRect)
            case .special:
                continue
            }
        }

        context.restoreGState()
    }

    private func draw(glyph: DVIGlyph, in pageRect: NSRect, document: DVIDocument) {
        let definition = document.fonts[glyph.fontNumber]
        let texName = definition?.name ?? ""
        if let definition,
           let type1Font = type1FontProvider?.font(for: definition),
           let glyphName = TeXGlyphMapper.glyphName(for: glyph.characterCode, fontName: texName),
           let glyphPath = type1Font.path(forGlyphNamed: glyphName) {
            draw(type1Path: glyphPath, font: type1Font, glyph: glyph, in: pageRect)
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
