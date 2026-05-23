import Foundation

struct TFMCharacterMetric {
    let widthDVIUnits: Int64
    let heightDVIUnits: Int64
    let depthDVIUnits: Int64
    let italicCorrectionDVIUnits: Int64
}

final class TFMFontMetric {
    let checksum: UInt32
    let designSize: Int32
    let parameters: [Int32]

    private let firstCharacter: Int
    private let lastCharacter: Int
    private let characterInfos: [TFMCharacterInfo]
    private let widths: [Int32]
    private let heights: [Int32]
    private let depths: [Int32]
    private let italicCorrections: [Int32]

    init(data: Data) throws {
        var reader = TFMReader(data: data)
        let lf = try reader.readUInt16()
        let lh = try reader.readUInt16()
        let bc = try reader.readUInt16()
        let ec = try reader.readUInt16()
        let nw = try reader.readUInt16()
        let nh = try reader.readUInt16()
        let nd = try reader.readUInt16()
        let ni = try reader.readUInt16()
        let nl = try reader.readUInt16()
        let nk = try reader.readUInt16()
        let ne = try reader.readUInt16()
        let np = try reader.readUInt16()

        guard lf > 0, nw > 0, nh > 0, nd > 0, ni > 0, ec >= bc || (bc == 1 && ec == 0) else {
            throw DVIError.malformed("invalid TFM header")
        }

        let characterCount = ec >= bc ? Int(ec - bc + 1) : 0
        let expectedWordCount = 6
            + Int(lh)
            + characterCount
            + Int(nw)
            + Int(nh)
            + Int(nd)
            + Int(ni)
            + Int(nl)
            + Int(nk)
            + Int(ne)
            + Int(np)
        guard Int(lf) >= expectedWordCount, data.count >= expectedWordCount * 4 else {
            throw DVIError.malformed("TFM table lengths exceed file length")
        }

        var headerWords: [Int32] = []
        headerWords.reserveCapacity(Int(lh))
        for _ in 0..<Int(lh) {
            headerWords.append(try reader.readInt32())
        }
        checksum = headerWords.isEmpty ? 0 : UInt32(bitPattern: headerWords[0])
        designSize = headerWords.count > 1 ? headerWords[1] : 0

        firstCharacter = Int(bc)
        lastCharacter = Int(ec)
        var infos: [TFMCharacterInfo] = []
        infos.reserveCapacity(characterCount)

        for _ in 0..<characterCount {
            let widthIndex = Int(try reader.readByte())
            let heightDepth = try reader.readByte()
            let italicTag = try reader.readByte()
            let remainder = Int(try reader.readByte())
            infos.append(TFMCharacterInfo(
                widthIndex: widthIndex,
                heightIndex: Int(heightDepth >> 4),
                depthIndex: Int(heightDepth & 0x0f),
                italicIndex: Int(italicTag >> 2),
                tag: Int(italicTag & 0x03),
                remainder: remainder
            ))
        }
        characterInfos = infos

        widths = try reader.readFixWords(count: Int(nw))
        heights = try reader.readFixWords(count: Int(nh))
        depths = try reader.readFixWords(count: Int(nd))
        italicCorrections = try reader.readFixWords(count: Int(ni))

        try reader.skip(Int(nl) * 4)
        try reader.skip(Int(nk) * 4)
        try reader.skip(Int(ne) * 4)
        parameters = try reader.readFixWords(count: Int(np))
    }

    func widthDVIUnits(for characterCode: Int, scaledSize: Int64) -> Int64? {
        characterMetric(for: characterCode, scaledSize: scaledSize)?.widthDVIUnits
    }

    func characterMetric(for characterCode: Int, scaledSize: Int64) -> TFMCharacterMetric? {
        guard characterCode >= firstCharacter, characterCode <= lastCharacter else {
            return nil
        }
        let infoIndex = characterCode - firstCharacter
        guard infoIndex >= 0 && infoIndex < characterInfos.count else {
            return nil
        }
        let info = characterInfos[infoIndex]
        guard info.widthIndex >= 0,
              info.widthIndex < widths.count,
              info.heightIndex >= 0,
              info.heightIndex < heights.count,
              info.depthIndex >= 0,
              info.depthIndex < depths.count,
              info.italicIndex >= 0,
              info.italicIndex < italicCorrections.count else {
            return nil
        }

        return TFMCharacterMetric(
            widthDVIUnits: scale(widths[info.widthIndex], by: scaledSize),
            heightDVIUnits: scale(heights[info.heightIndex], by: scaledSize),
            depthDVIUnits: scale(depths[info.depthIndex], by: scaledSize),
            italicCorrectionDVIUnits: scale(italicCorrections[info.italicIndex], by: scaledSize)
        )
    }

    private func scale(_ fixWord: Int32, by scaledSize: Int64) -> Int64 {
        let value = Int64(fixWord) * scaledSize
        let halfUnit: Int64 = 1 << 19
        if value >= 0 {
            return (value + halfUnit) >> 20
        }
        return -(((-value) + halfUnit) >> 20)
    }
}

final class TFMFontMetricProvider {
    private var cache: [String: TFMFontMetric] = [:]
    private var missingMetrics: Set<String> = []
    private let searchDirectories: [URL]

    init(documentURL: URL) {
        var directories = [documentURL.deletingLastPathComponent()]
        directories.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        self.searchDirectories = directories
    }

    func metric(for font: DVIFontDefinition) -> TFMFontMetric? {
        let key = font.texName.lowercased()
        if let cached = cache[key] {
            return cached
        }
        if missingMetrics.contains(key) {
            return nil
        }

        guard let metric = loadMetric(named: font.name, area: font.area) else {
            missingMetrics.insert(key)
            return nil
        }
        cache[key] = metric
        return metric
    }

    func metric(for fontName: String) -> TFMFontMetric? {
        let key = fontName.lowercased()
        if let cached = cache[key] {
            return cached
        }
        if missingMetrics.contains(key) {
            return nil
        }

        guard let metric = loadMetric(named: fontName, area: "") else {
            missingMetrics.insert(key)
            return nil
        }
        cache[key] = metric
        return metric
    }

    private func loadMetric(named fontName: String, area: String) -> TFMFontMetric? {
        for url in candidateURLs(fontName: fontName, area: area) {
            if let data = try? Data(contentsOf: url),
               let metric = try? TFMFontMetric(data: data) {
                return metric
            }
        }

        for name in kpathseaNames(fontName: fontName, area: area) {
            if let path = Kpathsea.findTFM(named: name),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let metric = try? TFMFontMetric(data: data) {
                return metric
            }
        }
        return nil
    }

    private func candidateURLs(fontName: String, area: String) -> [URL] {
        var urls: [URL] = []
        if !area.isEmpty {
            let areaURL = URL(fileURLWithPath: area, isDirectory: true)
            if areaURL.path.hasPrefix("/") {
                urls.append(areaURL.appendingPathComponent(fontName).appendingPathExtension("tfm"))
            }

            for directory in searchDirectories {
                urls.append(directory.appendingPathComponent(area).appendingPathComponent(fontName).appendingPathExtension("tfm"))
            }
        }

        for directory in searchDirectories {
            urls.append(directory.appendingPathComponent(fontName).appendingPathExtension("tfm"))
        }
        return urls
    }

    private func kpathseaNames(fontName: String, area: String) -> [String] {
        if area.isEmpty {
            return [fontName]
        }
        return [area + fontName, fontName]
    }
}

private struct TFMCharacterInfo {
    let widthIndex: Int
    let heightIndex: Int
    let depthIndex: Int
    let italicIndex: Int
    let tag: Int
    let remainder: Int
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

    mutating func readFixWords(count: Int) throws -> [Int32] {
        var words: [Int32] = []
        words.reserveCapacity(count)
        for _ in 0..<count {
            words.append(try readInt32())
        }
        return words
    }

    mutating func skip(_ count: Int) throws {
        guard offset + count <= data.count else {
            throw DVIError.malformed("unexpected end of TFM file")
        }
        offset += count
    }
}
