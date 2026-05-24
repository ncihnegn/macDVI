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

    static func glyphName(for characterCode: Int, fontName: String) -> String? {
        let lowercasedName = fontName.lowercased()
        if usesOT1Encoding(lowercasedName), let glyphName = ot1GlyphNames[characterCode] {
            return glyphName
        }
        return standardGlyphNames[characterCode]
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

    private static let ot1GlyphNames: [Int: String] = [
        0: "Gamma",
        1: "Delta",
        2: "Theta",
        3: "Lambda",
        4: "Xi",
        5: "Pi",
        6: "Sigma",
        7: "Upsilon",
        8: "Phi",
        9: "Psi",
        10: "Omega",
        11: "ff",
        12: "fi",
        13: "fl",
        14: "ffi",
        15: "ffl",
        16: "dotlessi",
        17: "dotlessj",
        18: "grave",
        19: "acute",
        20: "caron",
        21: "breve",
        22: "macron",
        23: "ring",
        24: "cedilla",
        25: "germandbls",
        26: "ae",
        27: "oe",
        28: "oslash",
        29: "AE",
        30: "OE",
        31: "Oslash",
        32: "space",
        33: "exclam",
        34: "quotedblright",
        35: "numbersign",
        36: "dollar",
        37: "percent",
        38: "ampersand",
        39: "quoteright",
        40: "parenleft",
        41: "parenright",
        42: "asterisk",
        43: "plus",
        44: "comma",
        45: "hyphen",
        46: "period",
        47: "slash",
        58: "colon",
        59: "semicolon",
        60: "exclamdown",
        61: "equal",
        62: "questiondown",
        63: "question",
        64: "at",
        91: "bracketleft",
        92: "quotedblleft",
        93: "bracketright",
        94: "circumflex",
        95: "dotaccent",
        96: "quoteleft",
        123: "endash",
        124: "emdash",
        125: "hungarumlaut",
        126: "tilde"
    ].merging(standardGlyphNames) { ot1, _ in ot1 }

    private static let standardGlyphNames: [Int: String] = [
        32: "space",
        33: "exclam",
        34: "quotedbl",
        35: "numbersign",
        36: "dollar",
        37: "percent",
        38: "ampersand",
        39: "quotesingle",
        40: "parenleft",
        41: "parenright",
        42: "asterisk",
        43: "plus",
        44: "comma",
        45: "hyphen",
        46: "period",
        47: "slash",
        48: "zero",
        49: "one",
        50: "two",
        51: "three",
        52: "four",
        53: "five",
        54: "six",
        55: "seven",
        56: "eight",
        57: "nine",
        58: "colon",
        59: "semicolon",
        60: "less",
        61: "equal",
        62: "greater",
        63: "question",
        64: "at",
        65: "A",
        66: "B",
        67: "C",
        68: "D",
        69: "E",
        70: "F",
        71: "G",
        72: "H",
        73: "I",
        74: "J",
        75: "K",
        76: "L",
        77: "M",
        78: "N",
        79: "O",
        80: "P",
        81: "Q",
        82: "R",
        83: "S",
        84: "T",
        85: "U",
        86: "V",
        87: "W",
        88: "X",
        89: "Y",
        90: "Z",
        91: "bracketleft",
        92: "backslash",
        93: "bracketright",
        94: "asciicircum",
        95: "underscore",
        96: "quoteleft",
        97: "a",
        98: "b",
        99: "c",
        100: "d",
        101: "e",
        102: "f",
        103: "g",
        104: "h",
        105: "i",
        106: "j",
        107: "k",
        108: "l",
        109: "m",
        110: "n",
        111: "o",
        112: "p",
        113: "q",
        114: "r",
        115: "s",
        116: "t",
        117: "u",
        118: "v",
        119: "w",
        120: "x",
        121: "y",
        122: "z",
        123: "braceleft",
        124: "bar",
        125: "braceright",
        126: "asciitilde"
    ]
}
