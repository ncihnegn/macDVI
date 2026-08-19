import Foundation

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
    let nativeMessage: String
    let conversionMessage: String

    var errorDescription: String? {
        """
        Could not open the DVI file.

        Native renderer: \(nativeMessage)

        Converter fallback: \(conversionMessage)
        """
    }
}

enum DVIDocumentLoader {
    static func load(url: URL) throws -> DVIDocumentLoadResult {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "ps", "eps":
            return .pdf(try PostScriptToPDFConverter.convert(postScriptURL: url))
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
