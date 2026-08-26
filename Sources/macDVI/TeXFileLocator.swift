import Foundation

enum TeXFileLocator {
    private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    static func findFile(named fileName: String) -> String? {
        lock.lock()
        if let cached = cache[fileName] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = runKpsewhich(arguments: [fileName])

        lock.lock()
        cache[fileName] = result
        lock.unlock()
        return result
    }

    static func findTFM(named fontName: String) -> String? {
        findFile(named: "\(fontName).tfm")
    }

    static func findPK(named fontName: String) -> String? {
        findFile(named: fontName, format: "pk")
    }

    static func findGF(named fontName: String) -> String? {
        findFile(named: fontName, format: "gf")
    }

    static func findFile(named fileName: String, format: String) -> String? {
        let cacheKey = "\(format):\(fileName)"
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let formatArg = "--format=\(format)"
        let result = runKpsewhich(arguments: [formatArg, fileName])

        lock.lock()
        cache[cacheKey] = result
        lock.unlock()
        return result
    }

    private static func runKpsewhich(arguments: [String]) -> String? {
        let executable = executablePath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = executable.hasSuffix("/env")
            ? ["kpsewhich"] + arguments
            : arguments

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
