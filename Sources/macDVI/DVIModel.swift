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
    case rule(DVIRule)
    case special(DVISpecial)
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
