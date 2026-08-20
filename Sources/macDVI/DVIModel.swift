import Foundation

struct DVIPreamble {
    let id: UInt8
    let numerator: Int64
    let denominator: Int64
    let magnification: Int64
    let comment: String

    var pointsPerDVIUnit: Double {
        guard denominator != 0 else { return 1.0 / 65536.0 }
        let metersPerDVIUnit = (Double(numerator) / Double(denominator)) * 0.0000001
        let pointsPerMeter = 72.0 / 0.0254
        return metersPerDVIUnit * pointsPerMeter * (Double(magnification) / 1000.0)
    }
}

struct DVIFontDefinition: Hashable {
    let number: Int
    let checksum: UInt32
    let scaledSize: Int64
    let designSize: Int64
    let area: String
    let name: String
    let isNative: Bool
    let nativeFlags: UInt16
    let nativeColor: DVIColor?
    let nativeExtend: Double?
    let nativeSlant: Double?
    let nativeEmbolden: Double?

    init(
        number: Int,
        checksum: UInt32,
        scaledSize: Int64,
        designSize: Int64,
        area: String,
        name: String,
        isNative: Bool = false,
        nativeFlags: UInt16 = 0,
        nativeColor: DVIColor? = nil,
        nativeExtend: Double? = nil,
        nativeSlant: Double? = nil,
        nativeEmbolden: Double? = nil
    ) {
        self.number = number
        self.checksum = checksum
        self.scaledSize = scaledSize
        self.designSize = designSize
        self.area = area
        self.name = name
        self.isNative = isNative
        self.nativeFlags = nativeFlags
        self.nativeColor = nativeColor
        self.nativeExtend = nativeExtend
        self.nativeSlant = nativeSlant
        self.nativeEmbolden = nativeEmbolden
    }

    var texName: String {
        if area.isEmpty {
            return name
        }
        return area + name
    }
}

struct DVIDocument {
    let url: URL
    let preamble: DVIPreamble
    let fonts: [Int: DVIFontDefinition]
    let pages: [DVIPage]
    let warnings: [String]
}

struct DVIPage {
    let number: Int
    let counters: [Int64]
    let items: [DVIPageItem]
    let mediaBox: CGSize
}

enum DVIPageItem {
    case glyph(DVIGlyph)
    case nativeGlyphArray(DVINativeGlyphArray)
    case pic(XDVPicItem)
    case rule(DVIRule)
    case special(DVISpecial)
}

struct XDVPicItem {
    let flags: UInt8
    let transform: [Double] // 6 elements: a, b, c, d, tx, ty
    let pageNumber: Int
    let path: String
    let x: Double
    let y: Double
}

struct DVINativeGlyphPosition: Hashable {
    let x: Double
    let y: Double
    let glyphID: UInt16
}

struct DVINativeGlyphArray {
    let fontNumber: Int
    let width: Double
    let glyphs: [DVINativeGlyphPosition]
    let x: Double
    let baselineY: Double
    let fontSize: Double
    let color: DVIColor
}

struct DVIGlyph {
    let fontNumber: Int
    let characterCode: Int
    let x: Double
    let baselineY: Double
    let advance: Double
    let height: Double
    let depth: Double
    let italicCorrection: Double
    let fontSize: Double
    let color: DVIColor
}

struct DVIRule {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let color: DVIColor
}

struct DVISpecial {
    let x: Double
    let y: Double
    let text: String
}

struct DVIColor: Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let black = DVIColor(red: 0, green: 0, blue: 0, alpha: 1)
}

enum DVIError: LocalizedError {
    case emptyFile
    case invalidPreamble
    case malformed(String)
    case unsupportedOpcode(UInt8, offset: Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The DVI file is empty."
        case .invalidPreamble:
            return "The file does not start with a valid DVI preamble."
        case .malformed(let message):
            return "Malformed DVI file: \(message)"
        case .unsupportedOpcode(let opcode, let offset):
            return "Unsupported DVI opcode \(opcode) at byte offset \(offset)."
        }
    }
}
