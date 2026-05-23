import Foundation

enum TeXGlyphMapper {
    static func string(for characterCode: Int, fontName: String) -> String {
        let lowercasedName = fontName.lowercased()

        if usesOT1Encoding(lowercasedName), let mapped = ot1Map[characterCode] {
            return mapped
        }

        if let scalar = UnicodeScalar(characterCode), characterCode >= 32, characterCode <= 126 {
            return String(Character(scalar))
        }

        return "\u{FFFD}"
    }

    private static func usesOT1Encoding(_ fontName: String) -> Bool {
        fontName.hasPrefix("cmr")
            || fontName.hasPrefix("cmb")
            || fontName.hasPrefix("cmc")
            || fontName.hasPrefix("cmss")
            || fontName.hasPrefix("cmsl")
            || fontName.hasPrefix("cmti")
            || fontName.hasPrefix("cmtt")
            || fontName.hasPrefix("lmr")
            || fontName.hasPrefix("lmss")
            || fontName.hasPrefix("lmtt")
    }

    private static let ot1Map: [Int: String] = [
        0: "\u{0393}",
        1: "\u{0394}",
        2: "\u{0398}",
        3: "\u{039B}",
        4: "\u{039E}",
        5: "\u{03A0}",
        6: "\u{03A3}",
        7: "\u{03A5}",
        8: "\u{03A6}",
        9: "\u{03A8}",
        10: "\u{03A9}",
        11: "ff",
        12: "fi",
        13: "fl",
        14: "ffi",
        15: "ffl",
        16: "\u{0131}",
        17: "\u{0237}",
        18: "`",
        19: "\u{00B4}",
        20: "\u{02C7}",
        21: "\u{02D8}",
        22: "\u{00AF}",
        23: "\u{02DA}",
        24: "\u{00B8}",
        25: "\u{00DF}",
        26: "\u{00E6}",
        27: "\u{0153}",
        28: "\u{00F8}",
        29: "\u{00C6}",
        30: "\u{0152}",
        31: "\u{00D8}"
    ]
}
