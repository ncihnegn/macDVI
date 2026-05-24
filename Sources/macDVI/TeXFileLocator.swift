import Foundation

enum TeXFileLocator {
    static func findFile(named fileName: String) -> String? {
        let executable = executablePath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = executable.hasSuffix("/env")
            ? ["kpsewhich", fileName]
            : [fileName]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    static func findTFM(named fontName: String) -> String? {
        findFile(named: "\(fontName).tfm")
    }

    private static func executablePath() -> String {
        let common = [
            "/Library/TeX/texbin/kpsewhich",
            "/usr/texbin/kpsewhich"
        ]
        for path in common where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/env"
    }
}
