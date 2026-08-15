import Foundation

enum PostScriptToPDFConverter {
    private static let conversionTimeout: TimeInterval = 120

    static func convert(postScriptURL: URL) throws -> PDFConversion {
        guard let executable = findGhostscript() else {
            throw PostScriptConverterError.notFound
        }

        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("macDVI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let outputURL = temporaryDirectory
            .appendingPathComponent(postScriptURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-dSAFER",
            "-dBATCH",
            "-dNOPAUSE",
            "-sDEVICE=pdfwrite",
            "-sOutputFile=\(outputURL.path)"
        ]
        if postScriptURL.pathExtension.lowercased() == "eps" {
            process.arguments?.append("-dEPSCrop")
        }
        process.arguments?.append(postScriptURL.path)
        process.currentDirectoryURL = postScriptURL.deletingLastPathComponent()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            let completion = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in
                completion.signal()
            }
            try process.run()
            if completion.wait(timeout: .now() + conversionTimeout) == .timedOut {
                process.terminate()
                throw PostScriptConverterError.timedOut
            }
        } catch {
            if let converterError = error as? PostScriptConverterError {
                throw converterError
            }
            throw PostScriptConverterError.launchFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            throw PostScriptConverterError.failed(exitCode: process.terminationStatus)
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue > 0 else {
            throw PostScriptConverterError.failed(exitCode: process.terminationStatus)
        }

        return PDFConversion(pdfURL: outputURL, converterName: "Ghostscript", log: "")
    }

    private static func findGhostscript() -> String? {
        let commonDirectories = [
            "/Library/TeX/texbin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        for directory in pathDirectories + commonDirectories {
            let path = URL(fileURLWithPath: directory).appendingPathComponent("gs").path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

private enum PostScriptConverterError: LocalizedError {
    case notFound
    case launchFailed(String)
    case failed(exitCode: Int32)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Ghostscript was not found. Install Ghostscript and ensure the gs executable is on PATH."
        case .launchFailed(let message):
            return "Could not launch Ghostscript: \(message)"
        case .failed(let exitCode):
            return "Ghostscript could not render the PostScript file (exit code \(exitCode))."
        case .timedOut:
            return "Ghostscript took too long to render the PostScript file."
        }
    }
}
