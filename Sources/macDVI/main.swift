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
        if !document.warnings.isEmpty {
            print("Warnings: \(document.warnings.count)")
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
