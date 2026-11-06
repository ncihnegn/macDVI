import AppKit
import Foundation
import zlib

// MARK: - SyncTeX Data Structures

struct SyncTeXLocation: Equatable {
    let page: Int
    let tag: Int
    let file: String
    let line: Int
    let column: Int
    let x: Double // in points (pt)
    let y: Double // in points (pt)
    let width: Double // in points (pt)
    let height: Double // in points (pt)
    let depth: Double // in points (pt)
    let isBox: Bool

    var rect: CGRect {
        let top = y - height
        let h = max(height + depth, 1.0)
        let w = max(width, 1.0)
        return CGRect(x: x, y: top, width: w, height: h)
    }
}

struct SyncTeXResult: Equatable {
    let file: String
    let line: Int
    let column: Int
    let page: Int // 1-based page number
    let rect: CGRect // in document page points (pt)
    let point: CGPoint // in document page points (pt)
}

// MARK: - SyncTeX Parser

final class SyncTeXParser {
    private let synctexURL: URL
    private var inputs: [Int: String] = [:]
    private var recordsByPage: [Int: [SyncTeXLocation]] = [:]
    private var recordsByFileAndLine: [String: [Int: [SyncTeXLocation]]] = [:]

    init?(url: URL) {
        self.synctexURL = url
        guard parse() else { return nil }
    }

    private func decompressGzip(data: Data) -> Data? {
        var stream = z_stream()
        guard inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        data.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: rawBuffer.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)

            repeat {
                buffer.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(bufferSize)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR {
                        return
                    }
                    let bytesWritten = bufferSize - Int(stream.avail_out)
                    if bytesWritten > 0 {
                        output.append(outBuf.baseAddress!, count: bytesWritten)
                    }
                }
            } while stream.avail_out == 0
        }
        return output
    }

    private func parse() -> Bool {
        guard let rawData = try? Data(contentsOf: synctexURL) else { return false }

        let textData: Data
        if synctexURL.pathExtension.lowercased() == "gz" || rawData.starts(with: [0x1F, 0x8B]) {
            guard let decompressed = decompressGzip(data: rawData) else { return false }
            textData = decompressed
        } else {
            textData = rawData
        }

        guard let content = String(data: textData, encoding: .utf8) else { return false }

        let docDir = synctexURL.deletingLastPathComponent()
        var unit: Double = 1.0
        var mag: Double = 1000.0
        var xOffset: Double = 0.0
        var yOffset: Double = 0.0
        var currentPage = 1

        let factor = 65536.0

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Input:") {
                let parts = trimmed.dropFirst(6).split(separator: ":", maxSplits: 1)
                if parts.count == 2, let tag = Int(parts[0]) {
                    let rawPath = String(parts[1])
                    let fullPath = URL(fileURLWithPath: rawPath, relativeTo: docDir).standardized.path
                    self.inputs[tag] = fullPath
                }
            } else if trimmed.hasPrefix("Magnification:") {
                mag = Double(trimmed.dropFirst(14)) ?? 1000.0
            } else if trimmed.hasPrefix("Unit:") {
                unit = Double(trimmed.dropFirst(5)) ?? 1.0
            } else if trimmed.hasPrefix("X Offset:") {
                xOffset = Double(trimmed.dropFirst(9)) ?? 0.0
            } else if trimmed.hasPrefix("Y Offset:") {
                yOffset = Double(trimmed.dropFirst(9)) ?? 0.0
            } else if trimmed.hasPrefix("{") {
                if let p = Int(trimmed.dropFirst(1)) {
                    currentPage = p
                }
            } else if let first = trimmed.first, "([vhkx$".contains(first) {
                let rest = trimmed.dropFirst(1)
                let parts = rest.split(separator: ":")
                guard parts.count >= 2 else { return }

                let tagParts = parts[0].split(separator: ",")
                guard tagParts.count >= 2,
                      let tag = Int(tagParts[0]),
                      let lineNum = Int(tagParts[1]) else { return }

                let col = tagParts.count > 2 ? (Int(tagParts[2]) ?? 0) : 0

                let coordParts = parts[1].split(separator: ",")
                guard coordParts.count >= 2,
                      let xSp = Double(coordParts[0]),
                      let ySp = Double(coordParts[1]) else { return }

                var wSp = 0.0
                var hSp = 0.0
                var dSp = 0.0
                if parts.count >= 3 {
                    let dimParts = parts[2].split(separator: ",")
                    if dimParts.count >= 1 { wSp = Double(dimParts[0]) ?? 0.0 }
                    if dimParts.count >= 2 { hSp = Double(dimParts[1]) ?? 0.0 }
                    if dimParts.count >= 3 { dSp = Double(dimParts[2]) ?? 0.0 }
                }

                let spPerPt = unit * factor * (mag / 1000.0)
                let xPt = (xSp + xOffset) / spPerPt
                let yPt = (ySp + yOffset) / spPerPt
                let wPt = wSp / spPerPt
                let hPt = hSp / spPerPt
                let dPt = dSp / spPerPt

                let filePath = self.inputs[tag] ?? ""
                let isBox = (first == "[" || first == "(" || first == "h" || first == "v")

                let loc = SyncTeXLocation(
                    page: currentPage,
                    tag: tag,
                    file: filePath,
                    line: lineNum,
                    column: col,
                    x: xPt,
                    y: yPt,
                    width: wPt,
                    height: hPt,
                    depth: dPt,
                    isBox: isBox
                )

                self.recordsByPage[currentPage, default: []].append(loc)

                let fileKey = (filePath as NSString).lastPathComponent.lowercased()
                if self.recordsByFileAndLine[fileKey] == nil {
                    self.recordsByFileAndLine[fileKey] = [:]
                }
                self.recordsByFileAndLine[fileKey]?[lineNum, default: []].append(loc)
            }
        }

        return !inputs.isEmpty
    }

    // MARK: - Forward Sync (Source Line -> Document Position)

    func forwardSync(sourceFile: String, line: Int, column: Int? = nil) -> SyncTeXResult? {
        let fileKey = (sourceFile as NSString).lastPathComponent.lowercased()
        guard let lineMap = recordsByFileAndLine[fileKey] else {
            // Try matching by suffix or checking inputs
            for (key, map) in recordsByFileAndLine {
                if sourceFile.lowercased().hasSuffix(key) || key.hasSuffix(fileKey) {
                    return forwardSyncInLineMap(map, line: line, column: column)
                }
            }
            return nil
        }
        return forwardSyncInLineMap(lineMap, line: line, column: column)
    }

    private func forwardSyncInLineMap(_ lineMap: [Int: [SyncTeXLocation]], line: Int, column: Int?) -> SyncTeXResult? {
        // Try exact line
        if let locs = lineMap[line], !locs.isEmpty {
            return bestMatch(from: locs, column: column)
        }

        // Try nearby lines (closest line within +/- 15 lines)
        let candidates = lineMap.keys.filter { abs($0 - line) <= 15 }
            .sorted { abs($0 - line) < abs($1 - line) }

        for nearby in candidates {
            if let locs = lineMap[nearby], !locs.isEmpty {
                return bestMatch(from: locs, column: column)
            }
        }

        return nil
    }

    private func bestMatch(from locs: [SyncTeXLocation], column: Int?) -> SyncTeXResult? {
        // Prefer boxes with positive dimensions
        let boxes = locs.filter { $0.isBox && $0.width > 0 }
        let target = boxes.first ?? locs.first
        guard let loc = target else { return nil }

        let rect: CGRect
        if loc.width > 0 {
            rect = loc.rect
        } else {
            rect = CGRect(x: loc.x, y: loc.y - 10, width: 250, height: 14)
        }

        return SyncTeXResult(
            file: loc.file,
            line: loc.line,
            column: loc.column,
            page: loc.page,
            rect: rect,
            point: CGPoint(x: loc.x, y: loc.y)
        )
    }

    // MARK: - Backward Sync (Document Position -> Source Line)

    func backwardSync(page: Int, point: CGPoint) -> SyncTeXResult? {
        guard let pageLocs = recordsByPage[page], !pageLocs.isEmpty else { return nil }

        var bestLoc: SyncTeXLocation?
        var bestScore = Double.infinity

        for loc in pageLocs {
            let dx = loc.x - point.x
            let dy = loc.y - point.y
            let distSq = dx * dx + dy * dy

            var score = distSq

            if loc.isBox && loc.width > 0 {
                let hitRect = loc.rect.insetBy(dx: -4, dy: -4)
                if hitRect.contains(point) {
                    // Small box preference: prefer smaller containing boxes over giant page boxes
                    let area = max(loc.rect.width * loc.rect.height, 1.0)
                    score = area * 0.05
                } else {
                    let rx = max(hitRect.minX - point.x, 0, point.x - hitRect.maxX)
                    let ry = max(hitRect.minY - point.y, 0, point.y - hitRect.maxY)
                    score = (rx * rx + ry * ry) + 2000.0
                }
            } else {
                let vDist = abs(dy)
                let hDist = abs(dx)
                if vDist <= 14.0 {
                    // Same line: strong bonus for glyphs / horizontal points
                    score = vDist * 2.0 + hDist * 0.5
                } else {
                    score = vDist * vDist * 4.0 + hDist * hDist
                }
            }

            if score < bestScore {
                bestScore = score
                bestLoc = loc
            }
        }

        guard let loc = bestLoc else { return nil }
        return SyncTeXResult(
            file: loc.file,
            line: loc.line,
            column: loc.column,
            page: loc.page,
            rect: loc.rect,
            point: CGPoint(x: loc.x, y: loc.y)
        )
    }
}

// MARK: - SyncTeX Service

final class SyncTeXService {
    static let shared = SyncTeXService()

    private var cache: [URL: (parser: SyncTeXParser, modDate: Date)] = [:]

    func parser(for documentURL: URL) -> SyncTeXParser? {
        guard let synctexURL = locateSyncTeXFile(for: documentURL) else { return nil }

        let modDate = (try? FileManager.default.attributesOfItem(atPath: synctexURL.path)[.modificationDate] as? Date) ?? Date.distantPast

        if let cached = cache[documentURL], cached.modDate == modDate {
            return cached.parser
        }

        guard let parser = SyncTeXParser(url: synctexURL) else { return nil }
        cache[documentURL] = (parser, modDate)
        return parser
    }

    func locateSyncTeXFile(for documentURL: URL) -> URL? {
        let dir = documentURL.deletingLastPathComponent()
        let baseName = documentURL.deletingPathExtension().lastPathComponent
        let fullName = documentURL.lastPathComponent

        let candidates = [
            dir.appendingPathComponent("\(baseName).synctex.gz"),
            dir.appendingPathComponent("\(baseName).synctex"),
            dir.appendingPathComponent("\(fullName).synctex.gz"),
            dir.appendingPathComponent("\(fullName).synctex")
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    func forwardSync(documentURL: URL, sourceFile: String, line: Int, column: Int? = nil) -> SyncTeXResult? {
        guard let p = parser(for: documentURL) else { return nil }
        return p.forwardSync(sourceFile: sourceFile, line: line, column: column)
    }

    func backwardSync(documentURL: URL, page: Int, point: CGPoint) -> SyncTeXResult? {
        guard let p = parser(for: documentURL) else { return nil }
        return p.backwardSync(page: page, point: point)
    }
}

// MARK: - SyncTeX Editor Opener

enum SyncTeXEditorOpener {
    static func open(file: String, line: Int, column: Int = 1) {
        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        // 1. Check custom editor in environment
        if let customEditor = ProcessInfo.processInfo.environment["MACDVI_EDITOR"], !customEditor.isEmpty {
            let cmd = customEditor
                .replacingOccurrences(of: "%file", with: fileURL.path)
                .replacingOccurrences(of: "%line", with: "\(line)")
                .replacingOccurrences(of: "%col", with: "\(column)")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", cmd]
            try? task.run()
            return
        }

        // 2. Check for VS Code (code)
        if let codePath = findExecutable(named: "code") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: codePath)
            task.arguments = ["-g", "\(fileURL.path):\(line):\(column)"]
            try? task.run()
            return
        }

        // 3. Check for Cursor (cursor)
        if let cursorPath = findExecutable(named: "cursor") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: cursorPath)
            task.arguments = ["-g", "\(fileURL.path):\(line):\(column)"]
            try? task.run()
            return
        }

        // 4. Check for Zed (zed)
        if let zedPath = findExecutable(named: "zed") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: zedPath)
            task.arguments = ["\(fileURL.path):\(line):\(column)"]
            try? task.run()
            return
        }

        // 5. Check for Sublime Text (subl)
        if let sublPath = findExecutable(named: "subl") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: sublPath)
            task.arguments = ["\(fileURL.path):\(line):\(column)"]
            try? task.run()
            return
        }

        // 6. Check for MacVim (mvim)
        if let mvimPath = findExecutable(named: "mvim") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: mvimPath)
            task.arguments = ["+\(line)", fileURL.path]
            try? task.run()
            return
        }

        // 7. Check for BBEdit (bbedit)
        if let bbeditPath = findExecutable(named: "bbedit") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: bbeditPath)
            task.arguments = ["+\(line)", fileURL.path]
            try? task.run()
            return
        }

        // 8. Check for Emacsclient (emacsclient)
        if let emacsPath = findExecutable(named: "emacsclient") {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: emacsPath)
            task.arguments = ["-n", "+\(line):\(column)", fileURL.path]
            try? task.run()
            return
        }

        // 9. Fallback to NSWorkspace
        NSWorkspace.shared.open(fileURL)
    }

    private static func findExecutable(named name: String) -> String? {
        let standardPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in standardPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
}
