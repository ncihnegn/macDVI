import Foundation

enum TeXFileLocator {
    private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    private static let standardSearchDirectories: [URL] = {
        var dirs: [URL] = []
        let fm = FileManager.default

        let texliveRoot = "/usr/local/texlive"
        if let subdirs = try? fm.contentsOfDirectory(atPath: texliveRoot) {
            for sub in subdirs.sorted().reversed() {
                let base = "\(texliveRoot)/\(sub)"
                let dist = "\(base)/texmf-dist/fonts"
                let varfonts = "\(base)/texmf-var/fonts"
                let varmap1 = "\(base)/texmf-var/fonts/map/pdftex/updmap"
                let varmap2 = "\(base)/texmf-var/fonts/map/dvips/updmap"
                let mapdir = "\(base)/texmf-dist/fonts/map/pdftex/updmap"
                for path in [
                    "\(dist)/type1/public/amsfonts/cm",
                    "\(dist)/type1/public/amsfonts/symbols",
                    "\(dist)/type1/public/amsfonts/latx-fonts",
                    "\(dist)/type1/public/lm",
                    "\(dist)/tfm/public/cm",
                    "\(dist)/tfm/public/amsfonts/cmextra",
                    "\(dist)/tfm/public/amsfonts/symbols",
                    "\(dist)/tfm/public/lm",
                    "\(varfonts)/tfm/public/cm",
                    "\(dist)/vf/public/cm",
                    "\(dist)/vf/public/lm",
                    varmap1,
                    varmap2,
                    mapdir
                ] {
                    if fm.fileExists(atPath: path) {
                        dirs.append(URL(fileURLWithPath: path))
                    }
                }
            }
        }

        for root in ["/Library/TeX/Root/texmf-dist/fonts", "/opt/homebrew/share/texmf-dist/fonts"] {
            for sub in [
                "type1/public/amsfonts/cm",
                "type1/public/lm",
                "tfm/public/cm",
                "tfm/public/lm",
                "vf/public/cm",
                "vf/public/lm",
                "map/pdftex/updmap"
            ] {
                let path = "\(root)/\(sub)"
                if fm.fileExists(atPath: path) {
                    dirs.append(URL(fileURLWithPath: path))
                }
            }
        }

        return dirs
    }()

    static func findFile(named fileName: String) -> String? {
        lock.lock()
        if let cached = cache[fileName] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        for dir in standardSearchDirectories {
            let candidate = dir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                lock.lock()
                cache[fileName] = candidate.path
                lock.unlock()
                return candidate.path
            }
        }

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

        // Check standard directories first
        let targetName = fileName.contains(".") ? fileName : "\(fileName).\(format)"
        for dir in standardSearchDirectories {
            let candidate = dir.appendingPathComponent(targetName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                lock.lock()
                cache[cacheKey] = candidate.path
                lock.unlock()
                return candidate.path
            }
        }

        let formatArg = "--format=\(format)"
        let result = runKpsewhich(arguments: [formatArg, fileName])

        lock.lock()
        cache[cacheKey] = result
        lock.unlock()
        return result
    }

    static func prefetchFiles(named fileNames: [String]) {
        var stillMissing: [String] = []

        lock.lock()
        for name in fileNames {
            if cache.keys.contains(name) { continue }
            var foundPath: String?
            for dir in standardSearchDirectories {
                let candidate = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    foundPath = candidate.path
                    break
                }
            }
            if let foundPath {
                cache[name] = foundPath
            } else {
                stillMissing.append(name)
            }
        }
        lock.unlock()

        guard !stillMissing.isEmpty else { return }

        let executable = executablePath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = executable.hasSuffix("/env")
            ? ["kpsewhich"] + stillMissing
            : stillMissing

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return }

        let resolvedLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var resolvedMap: [String: String] = [:]
        for path in resolvedLines {
            let fileName = (path as NSString).lastPathComponent
            resolvedMap[fileName] = path
            resolvedMap[fileName.lowercased()] = path
        }

        lock.lock()
        for requested in stillMissing {
            if let found = resolvedMap[requested] ?? resolvedMap[requested.lowercased()] {
                cache[requested] = found
            } else {
                cache[requested] = nil
            }
        }
        lock.unlock()
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
            "/usr/local/bin/kpsewhich",
            "/Library/TeX/texbin/kpsewhich",
            "/opt/homebrew/bin/kpsewhich",
            "/usr/texbin/kpsewhich",
            "/usr/bin/kpsewhich"
        ]
        for path in common where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/env"
    }
}
