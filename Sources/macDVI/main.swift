import AppKit
import Foundation
import PDFKit

let arguments = Array(CommandLine.arguments.dropFirst())

if let inspectIndex = arguments.firstIndex(of: "--inspect") {
    var inspectArguments = arguments
    inspectArguments.remove(at: inspectIndex)
    guard let path = inspectArguments.first else {
        FileHandle.standardError.write(Data("usage: macDVI --inspect path/to/file\n".utf8))
        exit(64)
    }

    do {
        let url = URL(fileURLWithPath: path)
        if DVIDocumentLoader.isPDF(url: url) {
            guard let pdfDoc = PDFDocument(url: url) else {
                FileHandle.standardError.write(Data("Could not open PDF file at \(url.path)\n".utf8))
                exit(1)
            }
            print("PDF: \(url.lastPathComponent)")
            print("Pages: \(pdfDoc.pageCount)")
            if pdfDoc.isEncrypted {
                print("Encrypted: \(pdfDoc.isEncrypted)")
            }
            if pdfDoc.isLocked {
                print("Locked: \(pdfDoc.isLocked)")
            }
            if let attributes = pdfDoc.documentAttributes {
                if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
                    print("Title: \(title)")
                }
                if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
                    print("Author: \(author)")
                }
                if let creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String, !creator.isEmpty {
                    print("Creator: \(creator)")
                }
                if let producer = attributes[PDFDocumentAttribute.producerAttribute] as? String, !producer.isEmpty {
                    print("Producer: \(producer)")
                }
            }
            if let firstPage = pdfDoc.page(at: 0) {
                let bounds = firstPage.bounds(for: .mediaBox)
                print("Page 1 size: \(bounds.width) x \(bounds.height) pt")
            }
            exit(0)
        }

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
        FileHandle.standardError.write(Data("usage: macDVI --render-page file <pageNumber> <out.png>\n".utf8))
        exit(64)
    }
    let docURL = URL(fileURLWithPath: renderArgs[0])
    let outURL = URL(fileURLWithPath: renderArgs[2])
    do {
        if DVIDocumentLoader.isPDF(url: docURL) {
            guard let pdfDoc = PDFDocument(url: docURL) else {
                FileHandle.standardError.write(Data("could not open PDF file\n".utf8))
                exit(1)
            }
            guard pageNum >= 1, pageNum <= pdfDoc.pageCount else {
                FileHandle.standardError.write(Data("page out of bounds\n".utf8))
                exit(1)
            }
            guard let page = pdfDoc.page(at: pageNum - 1) else {
                FileHandle.standardError.write(Data("could not get page\n".utf8))
                exit(1)
            }
            let pageRect = page.bounds(for: .mediaBox)
            let img = page.thumbnail(of: pageRect.size, for: .mediaBox)
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                try png.write(to: outURL)
                print("Rendered page \(pageNum) to \(outURL.path)")
            }
            exit(0)
        }

        let doc = try DVIParser(url: docURL).parse()
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

if let searchTestIndex = arguments.firstIndex(of: "--test-search") {
    var searchArgs = arguments
    searchArgs.remove(at: searchTestIndex)
    guard searchArgs.count >= 2 else {
        FileHandle.standardError.write(Data("usage: macDVI --test-search <file> <query> [--case-sensitive]\n".utf8))
        exit(64)
    }
    let filePath = searchArgs[0]
    let query = searchArgs[1]
    let caseSensitive = searchArgs.contains("--case-sensitive")

    let url = URL(fileURLWithPath: filePath)
    if DVIDocumentLoader.isPDF(url: url) {
        guard let pdfDoc = PDFDocument(url: url) else {
            print("Failed to load PDF: \(url.path)")
            exit(1)
        }
        var options: NSString.CompareOptions = [.literal]
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        let matches = pdfDoc.findString(query, withOptions: options)
        print("PDF search for '\(query)' found \(matches.count) match(es):")
        for (i, m) in matches.enumerated() {
            let pageNum = m.pages.first.flatMap { pdfDoc.index(for: $0) + 1 } ?? 0
            print("  [\(i + 1)] Page \(pageNum): '\(m.string ?? "")'")
        }
        exit(0)
    } else {
        do {
            let doc = try DVIParser(url: url).parse()
            let engine = DVISearchEngine()
            let matches = engine.search(document: doc, query: query, caseSensitive: caseSensitive)
            print("DVI search for '\(query)' found \(matches.count) match(es):")
            for (i, m) in matches.enumerated() {
                print("  [\(i + 1)] Page \(m.pageIndex + 1): '\(m.text)' with \(m.rects.count) rect(s): \(m.rects)")
            }
            exit(0)
        } catch {
            print("DVI search error: \(error.localizedDescription)")
            exit(1)
        }
    }
}

let fileURLs = arguments
    .filter { !$0.hasPrefix("-") }
    .map { URL(fileURLWithPath: $0) }

let app = NSApplication.shared
let delegate = AppDelegate(initialFileURLs: fileURLs)
app.delegate = delegate
app.run()
