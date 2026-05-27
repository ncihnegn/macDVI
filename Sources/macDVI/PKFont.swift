import CoreGraphics
import Foundation

struct PKGlyph {
    let characterCode: Int
    let tfmWidth: UInt32
    let dx: Int32
    let dy: Int32
    let width: Int
    let height: Int
    let hoff: Int
    let voff: Int
    let bitmap: Data
}

final class PKFont {
    let designSizeFix: UInt32
    let checksum: UInt32
    let hpppFix: UInt32
    let vpppFix: UInt32
    let comment: String
    let glyphs: [Int: PKGlyph]

    var pixelsPerPoint: Double {
        Double(hpppFix) / Double(1 << 16)
    }

    var pointsPerPixel: Double {
        let ppp = pixelsPerPoint
        return ppp > 0 ? 1.0 / ppp : 1.0
    }

    init(data: Data) throws {
        var reader = DVIByteReader(data: data)
        let pre = try reader.readByte()
        guard pre == 247 else {
            throw DVIError.malformed("PK: missing preamble opcode")
        }
        let id = try reader.readByte()
        guard id == 89 else {
            throw DVIError.malformed("PK: unexpected id \(id)")
        }

        let commentLength = Int(try reader.readUnsigned(1))
        let commentBytes = try reader.readBytes(commentLength)
        comment = String(data: commentBytes, encoding: .utf8)
            ?? String(data: commentBytes, encoding: .ascii)
            ?? ""

        designSizeFix = UInt32(try reader.readUnsigned(4))
        checksum = UInt32(try reader.readUnsigned(4))
        hpppFix = UInt32(try reader.readUnsigned(4))
        vpppFix = UInt32(try reader.readUnsigned(4))

        var collected: [Int: PKGlyph] = [:]

    parse:
        while !reader.isAtEnd {
            let flag = try reader.readByte()

            if flag >= 240 {
                switch flag {
                case 240, 241, 242, 243:
                    let nbytes = Int(flag - 239)
                    let length = Int(try reader.readUnsigned(nbytes))
                    _ = try reader.readBytes(length)
                case 244:
                    _ = try reader.readBytes(4)
                case 245:
                    break parse
                case 246:
                    continue
                default:
                    break parse
                }
                continue
            }

            let dynF = Int(flag >> 4)
            let black0 = (flag & 0x08) != 0
            let kind = Int(flag & 0x07)

            let pl: Int
            let cc: Int
            let tfm: UInt32
            let dx: Int32
            let dy: Int32
            let width: Int
            let height: Int
            let hoff: Int
            let voff: Int
            let rsize: Int

            if kind < 4 {
                pl = ((kind & 0x3) << 8) | Int(try reader.readUnsigned(1))
                cc = Int(try reader.readUnsigned(1))
                tfm = UInt32(try reader.readUnsigned(3))
                let dm = UInt32(try reader.readUnsigned(1))
                dx = Int32(bitPattern: dm << 16)
                dy = 0
                width = Int(try reader.readUnsigned(1))
                height = Int(try reader.readUnsigned(1))
                hoff = Int(try reader.readSigned(1))
                voff = Int(try reader.readSigned(1))
                rsize = pl - 8
            } else if kind < 7 {
                pl = ((kind & 0x3) << 16) | Int(try reader.readUnsigned(2))
                cc = Int(try reader.readUnsigned(1))
                tfm = UInt32(try reader.readUnsigned(3))
                let dm = UInt32(try reader.readUnsigned(2))
                dx = Int32(bitPattern: dm << 16)
                dy = 0
                width = Int(try reader.readUnsigned(2))
                height = Int(try reader.readUnsigned(2))
                hoff = Int(try reader.readSigned(2))
                voff = Int(try reader.readSigned(2))
                rsize = pl - 13
            } else {
                pl = Int(try reader.readUnsigned(4))
                cc = Int(try reader.readUnsigned(4))
                tfm = UInt32(try reader.readUnsigned(4))
                dx = Int32(bitPattern: UInt32(try reader.readUnsigned(4)))
                dy = Int32(bitPattern: UInt32(try reader.readUnsigned(4)))
                width = Int(try reader.readUnsigned(4))
                height = Int(try reader.readUnsigned(4))
                hoff = Int(try reader.readSigned(4))
                voff = Int(try reader.readSigned(4))
                rsize = pl - 28
            }

            let raster = try reader.readBytes(max(0, rsize))
            let bitmap: Data
            if width <= 0 || height <= 0 {
                bitmap = Data()
            } else if dynF == 14 {
                bitmap = PKFont.decodeRaw(raster: raster, width: width, height: height)
            } else {
                bitmap = PKFont.decodePacked(
                    raster: raster,
                    dynF: dynF,
                    black0: black0,
                    width: width,
                    height: height
                )
            }

            collected[cc] = PKGlyph(
                characterCode: cc,
                tfmWidth: tfm,
                dx: dx,
                dy: dy,
                width: width,
                height: height,
                hoff: hoff,
                voff: voff,
                bitmap: bitmap
            )
        }

        glyphs = collected
    }

    private static func decodeRaw(raster: Data, width: Int, height: Int) -> Data {
        let rowBytes = (width + 7) / 8
        var output = Data(count: rowBytes * height)
        let totalBits = width * height
        output.withUnsafeMutableBytes { destPtr in
            guard let dest = destPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            raster.withUnsafeBytes { srcPtr in
                guard let src = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let srcCount = raster.count
                for bitIndex in 0..<totalBits {
                    let srcByte = bitIndex >> 3
                    if srcByte >= srcCount { return }
                    let srcBit = 7 - (bitIndex & 7)
                    let bit = (src[srcByte] >> srcBit) & 1
                    if bit != 0 {
                        let row = bitIndex / width
                        let col = bitIndex % width
                        let dstByte = row * rowBytes + (col >> 3)
                        let dstBit = 7 - (col & 7)
                        dest[dstByte] |= UInt8(1 << dstBit)
                    }
                }
            }
        }
        return output
    }

    private static func decodePacked(
        raster: Data,
        dynF: Int,
        black0: Bool,
        width: Int,
        height: Int
    ) -> Data {
        let rowBytes = (width + 7) / 8
        var output = [UInt8](repeating: 0, count: rowBytes * height)
        var nybbles = NybbleReader(data: raster)
        var pixelsRemaining = width * height
        var black = black0
        var x = 0
        var y = 0
        var rowAccum = [Bool](repeating: false, count: width)
        var pendingRepeat = 0

        func flushRow() {
            guard y < height else { return }
            let copies = pendingRepeat + 1
            for _ in 0..<copies {
                guard y < height else { return }
                for col in 0..<width where rowAccum[col] {
                    let dstByte = y * rowBytes + (col >> 3)
                    let dstBit = 7 - (col & 7)
                    output[dstByte] |= UInt8(1 << dstBit)
                }
                y += 1
            }
            pendingRepeat = 0
            for index in rowAccum.indices {
                rowAccum[index] = false
            }
        }

        while pixelsRemaining > 0 {
            let firstNyb = nybbles.read()
            if firstNyb == nil { break }
            let nyb = firstNyb!

            if nyb == 14 {
                pendingRepeat = readPackedNumber(reader: &nybbles, dynF: dynF)
                continue
            }
            if nyb == 15 {
                pendingRepeat = 1
                continue
            }

            let count = decodePackedNumber(firstNyb: nyb, reader: &nybbles, dynF: dynF)
            var remaining = count
            while remaining > 0 && y < height {
                let canFit = width - x
                let put = min(remaining, canFit)
                if black {
                    for i in 0..<put {
                        rowAccum[x + i] = true
                    }
                }
                x += put
                remaining -= put
                if x >= width {
                    flushRow()
                    x = 0
                }
            }
            pixelsRemaining -= count
            black.toggle()
        }

        return Data(output)
    }

    private static func decodePackedNumber(firstNyb: Int, reader: inout NybbleReader, dynF: Int) -> Int {
        let j = firstNyb
        if j == 0 {
            var leading = 1
            var nextNyb = 0
            repeat {
                guard let next = reader.read() else { return 0 }
                nextNyb = next
                if next == 0 {
                    leading += 1
                }
            } while nextNyb == 0
            var value = nextNyb
            for _ in 0..<leading {
                guard let next = reader.read() else { return 0 }
                value = (value << 4) + next
            }
            return value - 15 + (13 - dynF) * 16 + dynF
        }
        if j <= dynF {
            return j
        }
        if j < 14 {
            let extra = reader.read() ?? 0
            return (j - dynF - 1) * 16 + extra + dynF + 1
        }
        return 0
    }

    private static func readPackedNumber(reader: inout NybbleReader, dynF: Int) -> Int {
        guard let first = reader.read() else { return 0 }
        return decodePackedNumber(firstNyb: first, reader: &reader, dynF: dynF)
    }
}

private struct NybbleReader {
    private let data: Data
    private var byteIndex: Int = 0
    private var highNibble: Bool = true

    init(data: Data) {
        self.data = data
    }

    mutating func read() -> Int? {
        guard byteIndex < data.count else { return nil }
        let byte = data[byteIndex]
        let value: Int
        if highNibble {
            value = Int(byte >> 4) & 0x0F
            highNibble = false
        } else {
            value = Int(byte) & 0x0F
            highNibble = true
            byteIndex += 1
        }
        return value
    }
}

final class PKFontProvider {
    private var cache: [String: PKFont] = [:]
    private var missing: Set<String> = []
    private var maskCache: [PKMaskCacheKey: CGImage] = [:]
    private let searchDirectories: [URL]

    init(documentURL: URL) {
        searchDirectories = [
            documentURL.deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
    }

    func font(for definition: DVIFontDefinition) -> PKFont? {
        let key = definition.texName.lowercased()
        if let cached = cache[key] {
            return cached
        }
        if missing.contains(key) {
            return nil
        }
        guard let url = locatePK(definition),
              let data = try? Data(contentsOf: url),
              let font = try? PKFont(data: data) else {
            missing.insert(key)
            return nil
        }
        cache[key] = font
        return font
    }

    func maskImage(for glyph: PKGlyph, fontKey: String) -> CGImage? {
        if glyph.width <= 0 || glyph.height <= 0 || glyph.bitmap.isEmpty {
            return nil
        }
        let key = PKMaskCacheKey(fontKey: fontKey, characterCode: glyph.characterCode)
        if let cached = maskCache[key] {
            return cached
        }
        let bytesPerRow = (glyph.width + 7) / 8
        guard let provider = CGDataProvider(data: glyph.bitmap as CFData) else { return nil }
        let decode: [CGFloat] = [1.0, 0.0]
        guard let mask = decode.withUnsafeBufferPointer({ buffer in
            CGImage(
                maskWidth: glyph.width,
                height: glyph.height,
                bitsPerComponent: 1,
                bitsPerPixel: 1,
                bytesPerRow: bytesPerRow,
                provider: provider,
                decode: buffer.baseAddress,
                shouldInterpolate: false
            )
        }) else {
            return nil
        }
        maskCache[key] = mask
        return mask
    }

    private func locatePK(_ definition: DVIFontDefinition) -> URL? {
        let baseNames = definition.area.isEmpty
            ? [definition.name]
            : [definition.area + definition.name, definition.name]

        let extensions = ["pk", "600pk", "300pk", "1200pk"]
        for directory in searchDirectories {
            for base in baseNames {
                for ext in extensions {
                    let url = directory.appendingPathComponent("\(base).\(ext)")
                    if FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                }
            }
        }

        if !definition.area.isEmpty {
            let areaURL = URL(fileURLWithPath: definition.area, isDirectory: true)
            if areaURL.path.hasPrefix("/") {
                for base in baseNames {
                    for ext in extensions {
                        let url = areaURL.appendingPathComponent("\(base).\(ext)")
                        if FileManager.default.fileExists(atPath: url.path) {
                            return url
                        }
                    }
                }
            }
        }

        for base in baseNames {
            if let path = TeXFileLocator.findPK(named: base) {
                return URL(fileURLWithPath: path)
            }
            for ext in extensions {
                if let path = TeXFileLocator.findFile(named: "\(base).\(ext)") {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }
}

private struct PKMaskCacheKey: Hashable {
    let fontKey: String
    let characterCode: Int
}
