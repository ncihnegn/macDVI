import CoreGraphics
import Foundation

struct GFGlyph {
    let characterCode: Int
    let tfmFix: UInt32
    let dx: Int32
    let dy: Int32
    let width: Int
    let height: Int
    let hoff: Int
    let voff: Int
    let bitmap: Data
}

final class GFFont {
    let designSizeFix: UInt32
    let checksum: UInt32
    let hpppFix: UInt32
    let vpppFix: UInt32
    let comment: String
    let glyphs: [Int: GFGlyph]

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
            throw DVIError.malformed("GF: missing preamble opcode")
        }
        let id = try reader.readByte()
        guard id == 131 else {
            throw DVIError.malformed("GF: unexpected id \(id)")
        }
        let commentLength = Int(try reader.readUnsigned(1))
        let commentBytes = try reader.readBytes(commentLength)
        comment = String(data: commentBytes, encoding: .utf8)
            ?? String(data: commentBytes, encoding: .ascii)
            ?? ""

        var collected: [Int: GFGlyph] = [:]
        var charWidths: [Int: UInt32] = [:]
        var design: UInt32 = 0
        var sum: UInt32 = 0
        var hppp: UInt32 = 0
        var vppp: UInt32 = 0

    parse:
        while !reader.isAtEnd {
            let opcode = try reader.readByte()
            switch opcode {
            case 67:
                let cc = Int(try reader.readSigned(4))
                _ = try reader.readSigned(4)
                let minM = try reader.readSigned(4)
                let maxM = try reader.readSigned(4)
                let minN = try reader.readSigned(4)
                let maxN = try reader.readSigned(4)
                if let glyph = try GFFont.decodeCharacter(
                    reader: &reader,
                    characterCode: cc,
                    minM: Int(minM),
                    maxM: Int(maxM),
                    minN: Int(minN),
                    maxN: Int(maxN)
                ) {
                    collected[cc] = glyph
                }
            case 68:
                let cc = Int(try reader.readUnsigned(1))
                let dm = Int(try reader.readUnsigned(1))
                let maxM = Int(try reader.readSigned(1))
                let dn = Int(try reader.readUnsigned(1))
                let maxN = Int(try reader.readSigned(1))
                let minM = maxM - dm
                let minN = maxN - dn
                if let glyph = try GFFont.decodeCharacter(
                    reader: &reader,
                    characterCode: cc,
                    minM: minM,
                    maxM: maxM,
                    minN: minN,
                    maxN: maxN
                ) {
                    collected[cc] = glyph
                }
            case 239...242:
                let length = Int(try reader.readUnsigned(Int(opcode - 238)))
                _ = try reader.readBytes(length)
            case 243...246:
                _ = try reader.readBytes(Int(opcode - 242))
                _ = try reader.readBytes(4)
            case 247:
                let i = Int(try reader.readUnsigned(1))
                _ = try reader.readBytes(i)
            case 248:
                _ = try reader.readBytes(4)
                design = UInt32(try reader.readUnsigned(4))
                sum = UInt32(try reader.readUnsigned(4))
                hppp = UInt32(try reader.readUnsigned(4))
                vppp = UInt32(try reader.readUnsigned(4))
                _ = try reader.readBytes(16)

                while !reader.isAtEnd {
                    let postOp = try reader.readByte()
                    if postOp == 245 {
                        break
                    }
                    if postOp == 246 {
                        continue
                    }
                    if postOp == 249 {
                        break parse
                    }
                    let cc = Int(try reader.readUnsigned(1))
                    let widthFix = UInt32(try reader.readUnsigned(4))
                    _ = try reader.readBytes(4)
                    charWidths[cc] = widthFix
                    if postOp == 245 {
                        break
                    }
                }
                break parse
            case 249:
                break parse
            default:
                continue
            }
        }

        designSizeFix = design
        checksum = sum
        hpppFix = hppp
        vpppFix = vppp

        var merged: [Int: GFGlyph] = [:]
        for (cc, glyph) in collected {
            if let widthFix = charWidths[cc] {
                merged[cc] = GFGlyph(
                    characterCode: cc,
                    tfmFix: widthFix,
                    dx: glyph.dx,
                    dy: glyph.dy,
                    width: glyph.width,
                    height: glyph.height,
                    hoff: glyph.hoff,
                    voff: glyph.voff,
                    bitmap: glyph.bitmap
                )
            } else {
                merged[cc] = glyph
            }
        }
        glyphs = merged
    }

    private static func decodeCharacter(
        reader: inout DVIByteReader,
        characterCode: Int,
        minM: Int,
        maxM: Int,
        minN: Int,
        maxN: Int
    ) throws -> GFGlyph? {
        let width = max(0, maxM - minM + 1)
        let height = max(0, maxN - minN + 1)
        let rowBytes = (width + 7) / 8
        var output = [UInt8](repeating: 0, count: rowBytes * height)
        var currentRow = -1
        var m = 0
        var paintBlack = false

        func paint(_ length: Int) {
            if currentRow >= 0 && currentRow < height && paintBlack {
                let start = max(0, m)
                let end = min(width, m + length)
                if start < end {
                    let rowOffset = currentRow * rowBytes
                    for col in start..<end {
                        output[rowOffset + (col >> 3)] |= UInt8(0x80 >> (col & 7))
                    }
                }
            }
            m += length
        }

    char:
        while !reader.isAtEnd {
            let opcode = try reader.readByte()
            switch opcode {
            case 0...63:
                paint(Int(opcode))
                paintBlack.toggle()
            case 64...66:
                let length = Int(try reader.readUnsigned(Int(opcode - 63)))
                paint(length)
                paintBlack.toggle()
            case 69:
                break char
            case 70:
                currentRow = currentRow < 0 ? 0 : currentRow + 1
                m = 0
                paintBlack = false
            case 71...73:
                let k = Int(try reader.readUnsigned(Int(opcode - 70)))
                currentRow = (currentRow < 0 ? 0 : currentRow + 1) + k
                m = 0
                paintBlack = false
            case 74...238:
                currentRow = currentRow < 0 ? 0 : currentRow + 1
                m = Int(opcode) - 74
                paintBlack = true
            case 239...242:
                let length = Int(try reader.readUnsigned(Int(opcode - 238)))
                _ = try reader.readBytes(length)
            case 243...246:
                _ = try reader.readBytes(Int(opcode - 242))
                _ = try reader.readBytes(4)
            case 247:
                break char
            default:
                continue
            }
        }

        guard width > 0, height > 0 else {
            return GFGlyph(
                characterCode: characterCode,
                tfmFix: 0,
                dx: 0,
                dy: 0,
                width: 0,
                height: 0,
                hoff: -minM,
                voff: maxN,
                bitmap: Data()
            )
        }

        return GFGlyph(
            characterCode: characterCode,
            tfmFix: 0,
            dx: 0,
            dy: 0,
            width: width,
            height: height,
            hoff: -minM,
            voff: maxN,
            bitmap: Data(output)
        )
    }
}

final class GFFontProvider {
    private var cache: [String: GFFont] = [:]
    private var missing: Set<String> = []
    private var maskCache: [GFMaskCacheKey: CGImage] = [:]
    private let searchDirectories: [URL]

    init(documentURL: URL) {
        searchDirectories = [
            documentURL.deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
    }

    func font(for definition: DVIFontDefinition) -> GFFont? {
        let key = definition.texName.lowercased()
        if let cached = cache[key] {
            return cached
        }
        if missing.contains(key) {
            return nil
        }
        guard let url = locateGF(definition),
              let data = try? Data(contentsOf: url),
              let font = try? GFFont(data: data) else {
            missing.insert(key)
            return nil
        }
        cache[key] = font
        return font
    }

    func maskImage(for glyph: GFGlyph, fontKey: String) -> CGImage? {
        if glyph.width <= 0 || glyph.height <= 0 || glyph.bitmap.isEmpty {
            return nil
        }
        let key = GFMaskCacheKey(fontKey: fontKey, characterCode: glyph.characterCode)
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

    private func locateGF(_ definition: DVIFontDefinition) -> URL? {
        let baseNames = definition.area.isEmpty
            ? [definition.name]
            : [definition.area + definition.name, definition.name]
        let extensions = ["gf", "600gf", "300gf", "1200gf"]

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
            if let path = TeXFileLocator.findGF(named: base) {
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

private struct GFMaskCacheKey: Hashable {
    let fontKey: String
    let characterCode: Int
}
