import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

if let inspectIndex = arguments.firstIndex(of: "--inspect") {
    var inspectArguments = arguments
    inspectArguments.remove(at: inspectIndex)
    guard let path = inspectArguments.first else {
        FileHandle.standardError.write(Data("usage: macDVI --inspect path/to/file.dvi\n".utf8))
        exit(64)
    }

    do {
        let url = URL(fileURLWithPath: path)
        let document = try DVIParser(url: url).parse()
        print("DVI: \(url.lastPathComponent)")
        print("Pages: \(document.pages.count)")
        print("Fonts: \(document.fonts.values.map { $0.name }.sorted().joined(separator: ", "))")
        let type1Provider = Type1FontProvider(documentURL: url)
        let type1Fonts = document.fonts.values
            .compactMap { type1Provider.font(for: $0)?.postScriptName }
            .sorted()
        if !type1Fonts.isEmpty {
            print("Type 1 fonts: \(type1Fonts.joined(separator: ", "))")
        }
        var graphics: [String] = []
        for (pageIdx, page) in document.pages.enumerated() {
            for item in page.items {
                if case .psGraphic(let g) = item {
                    graphics.append("Page \(pageIdx + 1): \(g.filePath) at (\(g.x), \(g.y)) (\(g.targetWidth)x\(g.targetHeight))")
                }
            }
        }
        if let p1 = document.pages.first {
            for item in p1.items {
                if case .glyph(let g) = item, g.characterCode == 79 { // 'O'
                    print("Glyph 'O' at x=\(g.x), baselineY=\(g.baselineY)")
                }
            }
        }
        if !graphics.isEmpty {
            print("Graphics (\(graphics.count)):\n  " + graphics.joined(separator: "\n  "))
        }
        print("PostScript headers: \(document.postScriptHeaders.count)")
        let page1PSCount = document.pages.first?.items.filter {
            if case .psInline = $0 { return true }
            return false
        }.count ?? 0
        print("Page 1 inline PostScript items: \(page1PSCount)")
        if !document.warnings.isEmpty {
            print("Warnings: \(document.warnings.count)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if let renderIndex = arguments.firstIndex(of: "--render-page") {
    var renderArgs = arguments
    renderArgs.remove(at: renderIndex)
    guard renderArgs.count >= 3,
          let pageNum = Int(renderArgs[1]) else {
        FileHandle.standardError.write(Data("usage: macDVI --render-page file.dvi <pageNumber> <out.png>\n".utf8))
        exit(64)
    }
    let dviURL = URL(fileURLWithPath: renderArgs[0])
    let outURL = URL(fileURLWithPath: renderArgs[2])
    do {
        let doc = try DVIParser(url: dviURL).parse()
        guard pageNum >= 1, pageNum <= doc.pages.count else {
            FileHandle.standardError.write(Data("page out of bounds\n".utf8))
            exit(1)
        }
        let page = doc.pages[pageNum - 1]
        let pageRect = NSRect(origin: .zero, size: page.mediaBox)
        let view = DVIDocumentView(frame: pageRect)
        view.document = doc
        let img = view.pageImage(at: pageNum - 1, page: page, in: pageRect, document: doc)
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
            try png.write(to: outURL)
            print("Rendered page \(pageNum) to \(outURL.path)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if let loadTestIndex = arguments.firstIndex(of: "--load-test") {
    var loadTestArguments = arguments
    loadTestArguments.remove(at: loadTestIndex)
    guard let path = loadTestArguments.first else {
        FileHandle.standardError.write(Data("usage: macDVI --load-test path/to/file\n".utf8))
        exit(64)
    }

    do {
        let url = URL(fileURLWithPath: path)
        let result = try DVIDocumentLoader.load(url: url)
        switch result {
        case .pdf(let conversion):
            print("Loaded via \(conversion.converterName): \(conversion.pdfURL.path)")
        case .native(let document):
            print("Loaded natively: \(document.pages.count) page(s)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let fileURLs = arguments
    .filter { !$0.hasPrefix("-") }
    .map { URL(fileURLWithPath: $0) }

let app = NSApplication.shared
let delegate = AppDelegate(initialFileURLs: fileURLs)
app.delegate = delegate
app.run()
