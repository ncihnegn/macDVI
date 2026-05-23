import Foundation

final class TFMFontMetric {
    private let firstCharacter: Int
    private let lastCharacter: Int
    private let widthIndexes: [UInt8]
    private let widths: [Int32]

    init(data: Data) throws {
        var reader = TFMReader(data: data)
        let lf = try reader.readUInt16()
        let lh = try reader.readUInt16()
        let bc = try reader.readUInt16()
        let ec = try reader.readUInt16()
        let nw = try reader.readUInt16()
        _ = try reader.readUInt16()
        _ = try reader.readUInt16()
        _ = try reader.readUInt16()
        _ = try reader.readUInt16()
        _ = try reader.readUInt16()
        _ = try reader.readUInt16()
        _ = try reader.readUInt16()

        guard lf > 0, nw > 0, ec >= bc || (bc == 1 && ec == 0) else {
            throw DVIError.malformed("invalid TFM header")
        }

        try reader.skip(Int(lh) * 4)

        firstCharacter = Int(bc)
        lastCharacter = Int(ec)
        let characterCount = ec >= bc ? Int(ec - bc + 1) : 0
        var indexes: [UInt8] = []
        indexes.reserveCapacity(characterCount)

        for _ in 0..<characterCount {
            indexes.append(try reader.readByte())
            try reader.skip(3)
        }
        widthIndexes = indexes

        var parsedWidths: [Int32] = []
        parsedWidths.reserveCapacity(Int(nw))
        for _ in 0..<Int(nw) {
            parsedWidths.append(try reader.readInt32())
        }
        widths = parsedWidths
    }

    func widthDVIUnits(for characterCode: Int, scaledSize: Int64) -> Int64? {
        guard characterCode >= firstCharacter, characterCode <= lastCharacter else {
            return nil
        }
        let infoIndex = characterCode - firstCharacter
        guard infoIndex >= 0 && infoIndex < widthIndexes.count else {
            return nil
        }
        let widthIndex = Int(widthIndexes[infoIndex])
        guard widthIndex >= 0 && widthIndex < widths.count else {
            return nil
        }
        let fixWord = Int64(widths[widthIndex])
        return (fixWord * scaledSize) >> 20
    }
}

final class TFMFontMetricProvider {
    private var cache: [String: TFMFontMetric?] = [:]
    private let searchDirectories: [URL]

    init(documentURL: URL) {
        var directories = [documentURL.deletingLastPathComponent()]
        directories.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        self.searchDirectories = directories
    }

    func metric(for fontName: String) -> TFMFontMetric? {
        let key = fontName.lowercased()
        if let cached = cache[key] {
            return cached
        }

        let metric = loadMetric(named: fontName)
        cache[key] = metric
        return metric
    }

    private func loadMetric(named fontName: String) -> TFMFontMetric? {
        for directory in searchDirectories {
            let url = directory.appendingPathComponent(fontName).appendingPathExtension("tfm")
            if let data = try? Data(contentsOf: url), let metric = try? TFMFontMetric(data: data) {
                return metric
            }
        }

        guard let path = Kpathsea.findTFM(named: fontName),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let metric = try? TFMFontMetric(data: data) else {
            return nil
        }
        return metric
    }
}

private enum Kpathsea {
    static func findTFM(named fontName: String) -> String? {
        let executable = executablePath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = executable.hasSuffix("/env")
            ? ["kpsewhich", "\(fontName).tfm"]
            : ["\(fontName).tfm"]

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

private struct TFMReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else {
            throw DVIError.malformed("unexpected end of TFM file")
        }
        let byte = data[offset]
        offset += 1
        return byte
    }

    mutating func readUInt16() throws -> UInt16 {
        let high = UInt16(try readByte())
        let low = UInt16(try readByte())
        return (high << 8) | low
    }

    mutating func readInt32() throws -> Int32 {
        let b0 = UInt32(try readByte())
        let b1 = UInt32(try readByte())
        let b2 = UInt32(try readByte())
        let b3 = UInt32(try readByte())
        let unsigned = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        return Int32(bitPattern: unsigned)
    }

    mutating func skip(_ count: Int) throws {
        guard offset + count <= data.count else {
            throw DVIError.malformed("unexpected end of TFM file")
        }
        offset += count
    }
}
