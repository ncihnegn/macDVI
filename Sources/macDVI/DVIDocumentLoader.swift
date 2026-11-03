import Foundation
import PDFKit

enum DVIDocumentLoadResult {
    case pdf(PDFConversion)
    case native(DVIDocument)
}

struct PDFConversion {
    let pdfURL: URL
    let converterName: String
    let log: String
}

struct DVIDocumentLoadError: LocalizedError {
    let message: String?
    let nativeMessage: String
    let conversionMessage: String

    init(message: String? = nil, nativeMessage: String, conversionMessage: String) {
        self.message = message
        self.nativeMessage = nativeMessage
        self.conversionMessage = conversionMessage
    }

    var errorDescription: String? {
        if let message {
            return message
        }
        return """
        Could not open the document.

        Native renderer: \(nativeMessage)

        Converter fallback: \(conversionMessage)
        """
    }
}

enum DVIDocumentLoader {
    static func isPDF(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return true
        }

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return false
        }

        let prefix = Array(data.prefix(1024))
        var start = 0
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) {
            start = 3
        }
        while start < prefix.count, prefix[start] == 0x09 || prefix[start] == 0x0A ||
                prefix[start] == 0x0C || prefix[start] == 0x0D || prefix[start] == 0x20 {
            start += 1
        }
        return prefix.dropFirst(start).starts(with: [0x25, 0x50, 0x44, 0x46, 0x2D]) // %PDF-
    }

    static func load(url: URL) throws -> DVIDocumentLoadResult {
        if isPDF(url: url) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw DVIDocumentLoadError(
                    message: "Could not open \(url.lastPathComponent): file does not exist.",
                    nativeMessage: "File does not exist: \(url.path)",
                    conversionMessage: "No conversion available for PDF"
                )
            }
            guard let document = PDFDocument(url: url) else {
                throw DVIDocumentLoadError(
                    message: "Could not open \(url.lastPathComponent): invalid or corrupted PDF file.",
                    nativeMessage: "Invalid or corrupted PDF file.",
                    conversionMessage: "No conversion available for PDF"
                )
            }
            guard document.pageCount > 0 else {
                throw DVIDocumentLoadError(
                    message: "Could not open \(url.lastPathComponent): PDF document contains no pages.",
                    nativeMessage: "PDF document contains no pages.",
                    conversionMessage: "No conversion available for PDF"
                )
            }
            return .pdf(PDFConversion(pdfURL: url, converterName: "PDFKit", log: ""))
        }

        let ext = url.pathExtension.lowercased()

        switch ext {
        case "ps", "eps":
            do {
                let document = try NativePostScriptLoader.load(url: url)
                return .native(document)
            } catch {
                let nativeMessage = error.localizedDescription
                do {
                    let conversion = try PostScriptToPDFConverter.convert(postScriptURL: url)
                    return .pdf(conversion)
                } catch {
                    throw DVIDocumentLoadError(
                        nativeMessage: nativeMessage,
                        conversionMessage: error.localizedDescription
                    )
                }
            }
        default:
            break
        }

        let isXDV = (ext == "xdv")

        do {
            let document = try DVIParser(url: url).parse()
            return .native(document)
        } catch {
            let nativeMessage = error.localizedDescription

            do {
                let conversion = try DVIToPDFConverter.convert(dviURL: url, preferXDV: isXDV)
                return .pdf(conversion)
            } catch {
                throw DVIDocumentLoadError(
                    nativeMessage: nativeMessage,
                    conversionMessage: error.localizedDescription
                )
            }
        }
    }
}

enum DVIToPDFConverter {
    static func convert(dviURL: URL, preferXDV: Bool = false) throws -> PDFConversion {
        let converterNames = preferXDV ? ["xdvipdfmx", "dvipdfmx"] : ["dvipdfmx"]
        var lastError: Error?

        for converterName in converterNames {
            guard let executable = findExecutable(named: converterName) else {
                lastError = ConverterError.notFound(converterName)
                continue
            }

            let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("macDVI-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let outputURL = temporaryDirectory
                .appendingPathComponent(dviURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("pdf")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["-o", outputURL.path, dviURL.path]
            process.currentDirectoryURL = dviURL.deletingLastPathComponent()

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                lastError = ConverterError.launchFailed(converterName, error.localizedDescription)
                continue
            }

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let log = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")

            guard process.terminationStatus == 0 else {
                lastError = ConverterError.failed(converterName, log.isEmpty ? "exit code \(process.terminationStatus)" : log)
                continue
            }

            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                lastError = ConverterError.failed(converterName, "converter completed but did not produce a PDF")
                continue
            }

            return PDFConversion(pdfURL: outputURL, converterName: converterName, log: log)
        }

        throw lastError ?? ConverterError.notFound(converterNames.first ?? "dvipdfmx")
    }

    private static func findExecutable(named name: String) -> String? {
        let commonDirectories = [
            "/Library/TeX/texbin",
            "/usr/texbin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        for directory in pathDirectories + commonDirectories {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

private enum ConverterError: LocalizedError {
    case notFound(String)
    case launchFailed(String, String)
    case failed(String, String)

    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "\(name) was not found."
        case .launchFailed(let executable, let message):
            return "Could not launch \(executable): \(message)"
        case .failed(let command, let log):
            return "\(command) failed: \(log)"
        }
    }
}
