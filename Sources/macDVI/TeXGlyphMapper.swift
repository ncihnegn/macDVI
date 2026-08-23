import Foundation

enum TeXGlyphMapper {
    static func string(for characterCode: Int, fontName: String) -> String {
        let encoding = encoding(for: fontName)
        if let mapped = unicode(forEncoding: encoding, characterCode: characterCode) {
            return mapped
        }
        if let scalar = UnicodeScalar(characterCode), characterCode >= 32, characterCode <= 126 {
            return String(Character(scalar))
        }
        return "\u{FFFD}"
    }

    static func glyphName(for characterCode: Int, fontName: String) -> String? {
        let encoding = encoding(for: fontName)
        if let name = glyphName(forEncoding: encoding, characterCode: characterCode) {
            return name
        }
        return standardGlyphNames[characterCode]
    }

    private enum Encoding {
        case ot1
        case ot1tt
        case oml
        case oms
        case omx
        case msam
        case msbm
        case t1
        case ascii
    }

    private static func encoding(for fontName: String) -> Encoding {
        let name = fontName.lowercased()

        if name.hasPrefix("cmtt") || name.hasPrefix("cmsltt") || name.hasPrefix("cmitt")
            || name.hasPrefix("cmtcsc") || name.hasPrefix("cmvtt")
            || name.hasPrefix("lmtt") || name.hasPrefix("lmtcsc") {
            return .ot1tt
        }
        if name.hasPrefix("cmmi") || name.hasPrefix("cmmib") || name.hasPrefix("lmmi") {
            return .oml
        }
        if name.hasPrefix("cmsy") || name.hasPrefix("cmbsy") || name.hasPrefix("lmsy") {
            return .oms
        }
        if name.hasPrefix("cmex") || name.hasPrefix("lmex") {
            return .omx
        }
        if name.hasPrefix("msam") {
            return .msam
        }
        if name.hasPrefix("msbm") {
            return .msbm
        }
        if name.hasPrefix("ec") || name.hasPrefix("tc")
            || name.hasPrefix("lmr") || name.hasPrefix("lmb")
            || name.hasPrefix("lmcsc") || name.hasPrefix("lmss")
            || name.hasPrefix("lmsl") || name.hasPrefix("lmri")
            || name.hasPrefix("lmu") {
            return .t1
        }
        if name.hasPrefix("cmr") || name.hasPrefix("cmb") || name.hasPrefix("cmbx")
            || name.hasPrefix("cmbxsl") || name.hasPrefix("cmbxti")
            || name.hasPrefix("cmcsc") || name.hasPrefix("cmdunh")
            || name.hasPrefix("cmff") || name.hasPrefix("cmfi")
            || name.hasPrefix("cmsl") || name.hasPrefix("cmss")
            || name.hasPrefix("cmti") || name.hasPrefix("cmu") {
            return .ot1
        }
        return .ascii
    }

    private static func unicode(forEncoding encoding: Encoding, characterCode code: Int) -> String? {
        switch encoding {
        case .ot1:
            return ot1Unicode[code] ?? printableASCII(code)
        case .ot1tt:
            return ot1ttUnicode[code] ?? printableASCII(code)
        case .oml:
            return omlUnicode[code]
        case .oms:
            return omsUnicode[code]
        case .omx:
            return omxUnicode[code]
        case .msam:
            return msamUnicode[code]
        case .msbm:
            return msbmUnicode[code]
        case .t1:
            return t1Unicode[code] ?? printableASCII(code)
        case .ascii:
            return printableASCII(code)
        }
    }

    private static func glyphName(forEncoding encoding: Encoding, characterCode code: Int) -> String? {
        switch encoding {
        case .ot1:
            return ot1GlyphNames[code]
        case .ot1tt:
            return ot1ttGlyphNames[code]
        case .oml:
            return omlGlyphNames[code]
        case .oms:
            return omsGlyphNames[code]
        case .omx:
            return omxGlyphNames[code]
        case .msam:
            return msamGlyphNames[code]
        case .msbm:
            return msbmGlyphNames[code]
        case .t1:
            return t1GlyphNames[code]
        case .ascii:
            return standardGlyphNames[code]
        }
    }

    private static func printableASCII(_ code: Int) -> String? {
        guard code >= 32, code <= 126, let scalar = UnicodeScalar(code) else { return nil }
        return String(Character(scalar))
    }

    private static let ot1Unicode: [Int: String] = [
        0: "\u{0393}", 1: "\u{0394}", 2: "\u{0398}", 3: "\u{039B}",
        4: "\u{039E}", 5: "\u{03A0}", 6: "\u{03A3}", 7: "\u{03A5}",
        8: "\u{03A6}", 9: "\u{03A8}", 10: "\u{03A9}",
        11: "ff", 12: "fi", 13: "fl", 14: "ffi", 15: "ffl",
        16: "\u{0131}", 17: "\u{0237}",
        18: "`", 19: "\u{00B4}", 20: "\u{02C7}", 21: "\u{02D8}",
        22: "\u{00AF}", 23: "\u{02DA}", 24: "\u{00B8}",
        25: "\u{00DF}", 26: "\u{00E6}", 27: "\u{0153}", 28: "\u{00F8}",
        29: "\u{00C6}", 30: "\u{0152}", 31: "\u{00D8}",
        34: "\u{201D}", 39: "\u{2019}",
        45: "-", 60: "\u{00A1}", 62: "\u{00BF}",
        92: "\u{201C}", 94: "\u{02C6}", 95: "\u{02D9}",
        96: "\u{2018}", 123: "\u{2013}", 124: "\u{2014}",
        125: "\u{02DD}", 126: "\u{02DC}", 127: "\u{00A8}"
    ]

    private static let ot1ttUnicode: [Int: String] = [
        0: "\u{0393}", 1: "\u{0394}", 2: "\u{0398}", 3: "\u{039B}",
        4: "\u{039E}", 5: "\u{03A0}", 6: "\u{03A3}", 7: "\u{03A5}",
        8: "\u{03A6}", 9: "\u{03A8}", 10: "\u{03A9}",
        11: "\u{2191}", 12: "\u{2193}", 13: "\u{0027}",
        14: "\u{00A1}", 15: "\u{00BF}",
        16: "\u{0131}", 17: "\u{0237}",
        18: "`", 19: "\u{00B4}", 20: "\u{02C7}", 21: "\u{02D8}",
        22: "\u{00AF}", 23: "\u{02DA}", 24: "\u{00B8}",
        25: "\u{00DF}", 26: "\u{00E6}", 27: "\u{0153}", 28: "\u{00F8}",
        29: "\u{00C6}", 30: "\u{0152}", 31: "\u{00D8}",
        32: "\u{2423}",
        92: "\u{201C}", 94: "\u{02C6}", 95: "\u{02D9}",
        96: "\u{2018}", 123: "\u{2013}", 124: "\u{2014}",
        125: "\u{02DD}", 126: "\u{02DC}", 127: "\u{00A8}"
    ]

    private static let omlUnicode: [Int: String] = [
        0: "\u{0393}", 1: "\u{0394}", 2: "\u{0398}", 3: "\u{039B}",
        4: "\u{039E}", 5: "\u{03A0}", 6: "\u{03A3}", 7: "\u{03A5}",
        8: "\u{03A6}", 9: "\u{03A8}", 10: "\u{03A9}",
        11: "\u{03B1}", 12: "\u{03B2}", 13: "\u{03B3}", 14: "\u{03B4}",
        15: "\u{03F5}", 16: "\u{03B6}", 17: "\u{03B7}", 18: "\u{03B8}",
        19: "\u{03B9}", 20: "\u{03BA}", 21: "\u{03BB}", 22: "\u{03BC}",
        23: "\u{03BD}", 24: "\u{03BE}", 25: "\u{03C0}", 26: "\u{03C1}",
        27: "\u{03C3}", 28: "\u{03C4}", 29: "\u{03C5}", 30: "\u{03D5}",
        31: "\u{03C7}",
        32: "\u{03C8}", 33: "\u{03C9}", 34: "\u{03B5}", 35: "\u{03D1}",
        36: "\u{03D6}", 37: "\u{03F1}", 38: "\u{03C2}", 39: "\u{03C6}",
        40: "\u{21BC}", 41: "\u{21BD}", 42: "\u{21C0}", 43: "\u{21C1}",
        44: "\u{02D3}", 45: "\u{02D2}", 46: "\u{25B7}", 47: "\u{25C1}",
        58: ".", 59: ",", 60: "<", 61: "/", 62: ">", 63: "\u{22C6}",
        64: "\u{2202}",
        91: "\u{266D}", 92: "\u{266E}", 93: "\u{266F}",
        94: "\u{2323}", 95: "\u{2322}",
        96: "\u{2113}", 123: "\u{0131}", 124: "\u{0237}",
        125: "\u{2118}", 126: "\u{20D7}", 127: "\u{0311}"
    ]

    private static let omsUnicode: [Int: String] = [
        0: "\u{2212}", 1: "\u{00B7}", 2: "\u{00D7}", 3: "\u{2217}",
        4: "\u{00F7}", 5: "\u{22C4}", 6: "\u{00B1}", 7: "\u{2213}",
        8: "\u{2295}", 9: "\u{2296}", 10: "\u{2297}", 11: "\u{2298}",
        12: "\u{2299}", 13: "\u{25CB}", 14: "\u{2218}", 15: "\u{2219}",
        16: "\u{224D}", 17: "\u{2261}", 18: "\u{2286}", 19: "\u{2287}",
        20: "\u{2264}", 21: "\u{2265}", 22: "\u{227C}", 23: "\u{227D}",
        24: "\u{223C}", 25: "\u{2248}", 26: "\u{2282}", 27: "\u{2283}",
        28: "\u{226A}", 29: "\u{226B}", 30: "\u{227A}", 31: "\u{227B}",
        32: "\u{2190}", 33: "\u{2192}", 34: "\u{2191}", 35: "\u{2193}",
        36: "\u{2194}", 37: "\u{2197}", 38: "\u{2198}", 39: "\u{2243}",
        40: "\u{21D0}", 41: "\u{21D2}", 42: "\u{21D1}", 43: "\u{21D3}",
        44: "\u{21D4}", 45: "\u{2196}", 46: "\u{2199}", 47: "\u{221D}",
        48: "\u{2032}", 49: "\u{221E}", 50: "\u{2208}", 51: "\u{220B}",
        52: "\u{25B3}", 53: "\u{25BD}", 54: "\u{0338}", 55: "\u{21A6}",
        56: "\u{2200}", 57: "\u{2203}", 58: "\u{00AC}", 59: "\u{2205}",
        60: "\u{211C}", 61: "\u{2111}", 62: "\u{22A4}", 63: "\u{22A5}",
        64: "\u{2135}",
        65: "\u{1D49C}", 66: "\u{212C}", 67: "\u{1D49E}", 68: "\u{1D49F}",
        69: "\u{2130}", 70: "\u{2131}", 71: "\u{1D4A2}", 72: "\u{210B}",
        73: "\u{2110}", 74: "\u{1D4A5}", 75: "\u{1D4A6}", 76: "\u{2112}",
        77: "\u{2133}", 78: "\u{1D4A9}", 79: "\u{1D4AA}", 80: "\u{1D4AB}",
        81: "\u{1D4AC}", 82: "\u{211B}", 83: "\u{1D4AE}", 84: "\u{1D4AF}",
        85: "\u{1D4B0}", 86: "\u{1D4B1}", 87: "\u{1D4B2}", 88: "\u{1D4B3}",
        89: "\u{1D4B4}", 90: "\u{1D4B5}",
        91: "\u{222A}", 92: "\u{2229}", 93: "\u{228E}", 94: "\u{2227}",
        95: "\u{2228}", 96: "\u{22A2}", 97: "\u{22A3}",
        98: "\u{230A}", 99: "\u{230B}", 100: "\u{2308}", 101: "\u{2309}",
        102: "{", 103: "}", 104: "\u{27E8}", 105: "\u{27E9}",
        106: "|", 107: "\u{2225}", 108: "\u{2195}", 109: "\u{21D5}",
        110: "\u{2216}", 111: "\u{2240}", 112: "\u{221A}", 113: "\u{2A3F}",
        114: "\u{2207}", 115: "\u{222B}", 116: "\u{2294}", 117: "\u{2293}",
        118: "\u{2291}", 119: "\u{2292}", 120: "\u{00A7}", 121: "\u{2020}",
        122: "\u{2021}", 123: "\u{00B6}", 124: "\u{2663}", 125: "\u{2662}",
        126: "\u{2661}", 127: "\u{2660}"
    ]

    private static let omxUnicode: [Int: String] = [
        0: "(", 1: ")", 2: "[", 3: "]",
        4: "\u{230A}", 5: "\u{230B}", 6: "\u{2308}", 7: "\u{2309}",
        8: "{", 9: "}", 10: "\u{27E8}", 11: "\u{27E9}",
        12: "|", 13: "\u{2225}", 14: "/", 15: "\u{2216}",
        16: "(", 17: ")", 18: "(", 19: ")", 20: "[", 21: "]",
        22: "\u{230A}", 23: "\u{230B}", 24: "\u{2308}", 25: "\u{2309}",
        26: "{", 27: "}", 28: "\u{27E8}", 29: "\u{27E9}",
        30: "/", 31: "\u{2216}",
        32: "(", 33: ")", 34: "[", 35: "]",
        36: "\u{230A}", 37: "\u{230B}", 38: "\u{2308}", 39: "\u{2309}",
        40: "{", 41: "}", 42: "\u{27E8}", 43: "\u{27E9}",
        44: "/", 45: "\u{2216}", 46: "/", 47: "\u{2216}",
        48: "\u{239B}", 49: "\u{239E}", 50: "\u{23A1}", 51: "\u{23A4}",
        52: "\u{23A3}", 53: "\u{23A6}", 54: "\u{23A2}", 55: "\u{23A5}",
        56: "\u{23A7}", 57: "\u{23AB}", 58: "\u{23A9}", 59: "\u{23AD}",
        60: "\u{23A8}", 61: "\u{23AC}", 62: "\u{23AA}", 63: "\u{2210}",
        64: "\u{239D}", 65: "\u{23A0}", 66: "\u{239C}", 67: "\u{239F}",
        68: "\u{27E8}", 69: "\u{27E9}",
        70: "\u{2294}", 71: "\u{2A06}", 72: "\u{222E}", 73: "\u{222E}",
        74: "\u{2299}", 75: "\u{2A00}", 76: "\u{2295}", 77: "\u{2A01}",
        78: "\u{2297}", 79: "\u{2A02}",
        80: "\u{2211}", 81: "\u{220F}", 82: "\u{222B}", 83: "\u{222A}",
        84: "\u{2229}", 85: "\u{228E}", 86: "\u{2227}", 87: "\u{2228}",
        88: "\u{2211}", 89: "\u{220F}", 90: "\u{222B}", 91: "\u{22C3}",
        92: "\u{22C2}", 93: "\u{2A04}", 94: "\u{22C0}", 95: "\u{22C1}",
        96: "\u{2210}", 97: "\u{2210}", 98: "^", 99: "^",
        100: "^", 101: "~", 102: "~", 103: "~",
        104: "[", 105: "]", 106: "\u{230A}", 107: "\u{230B}",
        108: "\u{2308}", 109: "\u{2309}", 110: "{", 111: "}",
        112: "\u{221A}", 113: "\u{221A}", 114: "\u{221A}", 115: "\u{221A}",
        116: "\u{23B7}", 117: "\u{23B7}", 118: "\u{23B7}", 119: "\u{2225}",
        120: "\u{2191}", 121: "\u{2193}", 122: "\u{23DF}", 123: "\u{23DF}",
        124: "\u{23DE}", 125: "\u{23DE}", 126: "\u{21D1}", 127: "\u{21D3}"
    ]

    private static let msamUnicode: [Int: String] = [
        0: "\u{229E}", 1: "\u{229F}", 2: "\u{22A0}", 3: "\u{22A1}",
        4: "\u{229D}", 5: "\u{229B}", 6: "\u{229A}", 7: "\u{229C}",
        8: "\u{22C7}", 9: "\u{22C9}", 10: "\u{22CA}", 11: "\u{22CB}",
        12: "\u{22CC}", 13: "\u{22CE}", 14: "\u{22CF}", 15: "\u{22D0}",
        16: "\u{22D1}", 17: "\u{22D2}", 18: "\u{22D3}", 19: "\u{22D4}",
        20: "\u{2256}", 21: "\u{2257}", 22: "\u{225C}", 23: "\u{2266}",
        24: "\u{2267}", 25: "\u{2268}", 26: "\u{2269}", 27: "\u{2A7D}",
        28: "\u{2A7E}", 29: "\u{2272}", 30: "\u{2273}", 31: "\u{2A95}",
        32: "\u{2A96}", 33: "\u{22DE}", 34: "\u{22DF}", 35: "\u{226C}",
        36: "\u{22DA}", 37: "\u{22DB}", 38: "\u{22D6}", 39: "\u{22D7}",
        40: "\u{2276}", 41: "\u{2277}", 42: "\u{22B2}", 43: "\u{22B3}",
        44: "\u{22B4}", 45: "\u{22B5}", 46: "\u{2234}", 47: "\u{2235}",
        48: "\u{2660}", 49: "\u{2661}", 50: "\u{2662}", 51: "\u{2663}",
        52: "\u{21BB}", 53: "\u{21BA}", 54: "\u{21CC}", 55: "\u{21CB}",
        56: "\u{21A0}", 57: "\u{219E}", 58: "\u{21C7}", 59: "\u{21C9}",
        60: "\u{21C8}", 61: "\u{21CA}", 62: "\u{21B6}", 63: "\u{21B7}",
        64: "\u{21CD}", 65: "\u{21CE}", 66: "\u{21CF}", 67: "\u{21DA}",
        68: "\u{21DB}", 69: "\u{2266}", 70: "\u{2267}", 71: "\u{2268}",
        72: "\u{2269}", 73: "\u{297D}", 74: "\u{297C}", 75: "\u{21A3}",
        76: "\u{21A2}", 77: "\u{21B0}", 78: "\u{21B1}", 79: "\u{21AB}",
        80: "\u{21AC}", 81: "\u{2933}", 82: "\u{22B8}", 83: "\u{2972}",
        84: "\u{2974}", 85: "\u{21AD}", 86: "\u{2220}", 87: "\u{2221}",
        88: "\u{2222}", 89: "\u{25B5}", 90: "\u{25BF}", 91: "\u{25EF}",
        92: "\u{1F846}", 93: "\u{2201}", 94: "\u{29EB}", 95: "\u{25A0}",
        96: "\u{25A1}", 97: "\u{2A7D}", 98: "\u{2A7E}", 99: "\u{2A85}",
        100: "\u{2A86}", 101: "\u{22D8}", 102: "\u{22D9}", 103: "\u{2266}",
        104: "\u{2267}", 105: "\u{2A8B}", 106: "\u{2A8C}", 107: "\u{22E6}",
        108: "\u{22E7}", 109: "\u{22E8}", 110: "\u{22E9}", 111: "\u{2A87}",
        112: "\u{2A88}", 113: "\u{227F}", 114: "\u{2270}", 115: "\u{2271}",
        116: "\u{226E}", 117: "\u{226F}", 118: "\u{2280}", 119: "\u{2281}",
        120: "\u{2268}", 121: "\u{2269}", 122: "\u{22E0}", 123: "\u{22E1}",
        124: "\u{2288}", 125: "\u{2289}", 126: "\u{2226}", 127: "\u{2224}"
    ]

    private static let msbmUnicode: [Int: String] = [
        0: "\u{226E}", 1: "\u{226F}", 2: "\u{2270}", 3: "\u{2271}",
        4: "\u{2A87}", 5: "\u{2A88}", 6: "\u{2A89}", 7: "\u{2A8A}",
        8: "\u{22E8}", 9: "\u{22E9}", 10: "\u{2A8B}", 11: "\u{2A8C}",
        12: "\u{2280}", 13: "\u{2281}", 14: "\u{2AB0}", 15: "\u{2AB1}",
        16: "\u{22E0}", 17: "\u{22E1}", 18: "\u{2226}", 19: "\u{2224}",
        20: "\u{2224}", 21: "\u{2226}", 22: "\u{2224}", 23: "\u{2226}",
        24: "\u{223D}", 25: "\u{2242}", 26: "\u{2249}", 27: "\u{2226}",
        28: "\u{226D}", 29: "\u{2204}", 30: "\u{2270}", 31: "\u{2271}",
        32: "\u{2288}", 33: "\u{2289}", 34: "\u{228A}", 35: "\u{228B}",
        36: "\u{2ACB}", 37: "\u{2ACC}", 38: "\u{228A}", 39: "\u{228B}",
        40: "\u{2226}", 41: "\u{2224}",
        65: "\u{1D538}", 66: "\u{1D539}", 67: "\u{2102}", 68: "\u{1D53B}",
        69: "\u{1D53C}", 70: "\u{1D53D}", 71: "\u{1D53E}", 72: "\u{210D}",
        73: "\u{1D540}", 74: "\u{1D541}", 75: "\u{1D542}", 76: "\u{1D543}",
        77: "\u{1D544}", 78: "\u{2115}", 79: "\u{1D546}", 80: "\u{2119}",
        81: "\u{211A}", 82: "\u{211D}", 83: "\u{1D54A}", 84: "\u{1D54B}",
        85: "\u{1D54C}", 86: "\u{1D54D}", 87: "\u{1D54E}", 88: "\u{1D54F}",
        89: "\u{1D550}", 90: "\u{2124}",
        107: "\u{006B}",
        121: "\u{2132}",
        123: "\u{2141}", 124: "\u{2127}", 125: "\u{210F}", 126: "\u{2136}",
        127: "\u{2137}"
    ]

    private static let t1Unicode: [Int: String] = [
        0: "\u{0060}", 1: "\u{00B4}", 2: "\u{02C6}", 3: "\u{02DC}",
        4: "\u{00A8}", 5: "\u{02DD}", 6: "\u{02DA}", 7: "\u{02C7}",
        8: "\u{02D8}", 9: "\u{00AF}", 10: "\u{02D9}", 11: "\u{00B8}",
        12: "\u{02DB}", 13: "\u{201A}", 14: "\u{2039}", 15: "\u{203A}",
        16: "\u{201C}", 17: "\u{201D}", 18: "\u{201E}", 19: "\u{00AB}",
        20: "\u{00BB}", 21: "\u{2013}", 22: "\u{2014}", 23: "\u{200C}",
        24: "\u{0131}", 25: "\u{0237}", 26: "ff", 27: "fi", 28: "fl",
        29: "ffi", 30: "ffl", 31: "\u{2423}",
        127: "\u{00AD}",
        128: "\u{0104}", 129: "\u{0118}", 130: "\u{0179}", 131: "\u{010E}",
        132: "\u{011A}", 133: "\u{0139}", 134: "\u{013D}", 135: "\u{0141}",
        136: "\u{0143}", 137: "\u{0147}", 138: "\u{014A}", 139: "\u{0150}",
        140: "\u{0154}", 141: "\u{0158}", 142: "\u{015A}", 143: "\u{0160}",
        144: "\u{015E}", 145: "\u{0164}", 146: "\u{0162}", 147: "\u{016E}",
        148: "\u{0170}", 149: "\u{0178}", 150: "\u{017D}", 151: "\u{0132}",
        152: "\u{0130}", 153: "\u{0111}", 154: "\u{00A7}", 155: "\u{0105}",
        156: "\u{0119}", 157: "\u{017A}", 158: "\u{010F}", 159: "\u{011B}",
        160: "\u{013A}", 161: "\u{013E}", 162: "\u{0142}", 163: "\u{0144}",
        164: "\u{0148}", 165: "\u{014B}", 166: "\u{0151}", 167: "\u{0155}",
        168: "\u{0159}", 169: "\u{015B}", 170: "\u{0161}", 171: "\u{015F}",
        172: "\u{0165}", 173: "\u{0163}", 174: "\u{016F}", 175: "\u{0171}",
        176: "\u{00FF}", 177: "\u{017E}", 178: "\u{0133}", 179: "\u{00A1}",
        180: "\u{00BF}", 181: "\u{00A3}", 182: "\u{00A4}", 183: "\u{20AC}",
        184: "\u{00A6}", 185: "\u{00BA}", 186: "\u{00AA}", 187: "\u{00A9}",
        188: "\u{00AE}", 189: "\u{2030}", 190: "\u{00B5}", 191: "\u{00B6}",
        192: "\u{00C0}", 193: "\u{00C1}", 194: "\u{00C2}", 195: "\u{00C3}",
        196: "\u{00C4}", 197: "\u{00C5}", 198: "\u{00C6}", 199: "\u{00C7}",
        200: "\u{00C8}", 201: "\u{00C9}", 202: "\u{00CA}", 203: "\u{00CB}",
        204: "\u{00CC}", 205: "\u{00CD}", 206: "\u{00CE}", 207: "\u{00CF}",
        208: "\u{00D0}", 209: "\u{00D1}", 210: "\u{00D2}", 211: "\u{00D3}",
        212: "\u{00D4}", 213: "\u{00D5}", 214: "\u{00D6}", 215: "\u{0152}",
        216: "\u{00D8}", 217: "\u{00D9}", 218: "\u{00DA}", 219: "\u{00DB}",
        220: "\u{00DC}", 221: "\u{00DD}", 222: "\u{00DE}", 223: "\u{00DF}",
        224: "\u{00E0}", 225: "\u{00E1}", 226: "\u{00E2}", 227: "\u{00E3}",
        228: "\u{00E4}", 229: "\u{00E5}", 230: "\u{00E6}", 231: "\u{00E7}",
        232: "\u{00E8}", 233: "\u{00E9}", 234: "\u{00EA}", 235: "\u{00EB}",
        236: "\u{00EC}", 237: "\u{00ED}", 238: "\u{00EE}", 239: "\u{00EF}",
        240: "\u{00F0}", 241: "\u{00F1}", 242: "\u{00F2}", 243: "\u{00F3}",
        244: "\u{00F4}", 245: "\u{00F5}", 246: "\u{00F6}", 247: "\u{0153}",
        248: "\u{00F8}", 249: "\u{00F9}", 250: "\u{00FA}", 251: "\u{00FB}",
        252: "\u{00FC}", 253: "\u{00FD}", 254: "\u{00FE}", 255: "\u{00DF}"
    ]

    private static let ot1GlyphNames: [Int: String] = [
        0: "Gamma", 1: "Delta", 2: "Theta", 3: "Lambda",
        4: "Xi", 5: "Pi", 6: "Sigma", 7: "Upsilon",
        8: "Phi", 9: "Psi", 10: "Omega",
        11: "ff", 12: "fi", 13: "fl", 14: "ffi", 15: "ffl",
        16: "dotlessi", 17: "dotlessj",
        18: "grave", 19: "acute", 20: "caron", 21: "breve",
        22: "macron", 23: "ring", 24: "cedilla",
        25: "germandbls", 26: "ae", 27: "oe", 28: "oslash",
        29: "AE", 30: "OE", 31: "Oslash",
        32: "space", 33: "exclam", 34: "quotedblright",
        35: "numbersign", 36: "dollar", 37: "percent",
        38: "ampersand", 39: "quoteright", 40: "parenleft",
        41: "parenright", 42: "asterisk", 43: "plus",
        44: "comma", 45: "hyphen", 46: "period", 47: "slash",
        48: "zero", 49: "one", 50: "two", 51: "three",
        52: "four", 53: "five", 54: "six", 55: "seven",
        56: "eight", 57: "nine",
        58: "colon", 59: "semicolon", 60: "exclamdown",
        61: "equal", 62: "questiondown", 63: "question",
        64: "at",
        91: "bracketleft", 92: "quotedblleft", 93: "bracketright",
        94: "circumflex", 95: "dotaccent", 96: "quoteleft",
        123: "endash", 124: "emdash", 125: "hungarumlaut",
        126: "tilde", 127: "dieresis"
    ].merging(uppercaseLetterNames) { ot1, _ in ot1 }
     .merging(lowercaseLetterNames) { ot1, _ in ot1 }

    private static let ot1ttGlyphNames: [Int: String] = [
        0: "Gamma", 1: "Delta", 2: "Theta", 3: "Lambda",
        4: "Xi", 5: "Pi", 6: "Sigma", 7: "Upsilon",
        8: "Phi", 9: "Psi", 10: "Omega",
        11: "arrowup", 12: "arrowdown", 13: "quotesingle",
        14: "exclamdown", 15: "questiondown",
        16: "dotlessi", 17: "dotlessj",
        18: "grave", 19: "acute", 20: "caron", 21: "breve",
        22: "macron", 23: "ring", 24: "cedilla",
        25: "germandbls", 26: "ae", 27: "oe", 28: "oslash",
        29: "AE", 30: "OE", 31: "Oslash",
        32: "visiblespace",
        33: "exclam", 34: "quotedbl", 35: "numbersign",
        36: "dollar", 37: "percent", 38: "ampersand",
        39: "quoteright", 40: "parenleft", 41: "parenright",
        42: "asterisk", 43: "plus", 44: "comma", 45: "hyphen",
        46: "period", 47: "slash",
        48: "zero", 49: "one", 50: "two", 51: "three",
        52: "four", 53: "five", 54: "six", 55: "seven",
        56: "eight", 57: "nine",
        58: "colon", 59: "semicolon", 60: "less", 61: "equal",
        62: "greater", 63: "question", 64: "at",
        91: "bracketleft", 92: "backslash", 93: "bracketright",
        94: "asciicircum", 95: "underscore", 96: "quoteleft",
        123: "braceleft", 124: "bar", 125: "braceright",
        126: "asciitilde", 127: "dieresis"
    ].merging(uppercaseLetterNames) { ot1, _ in ot1 }
     .merging(lowercaseLetterNames) { ot1, _ in ot1 }

    private static let omlGlyphNames: [Int: String] = [
        0: "Gamma", 1: "Delta", 2: "Theta", 3: "Lambda",
        4: "Xi", 5: "Pi", 6: "Sigma", 7: "Upsilon",
        8: "Phi", 9: "Psi", 10: "Omega",
        11: "alpha", 12: "beta", 13: "gamma", 14: "delta",
        15: "epsilon1", 16: "zeta", 17: "eta", 18: "theta",
        19: "iota", 20: "kappa", 21: "lambda", 22: "mu",
        23: "nu", 24: "xi", 25: "pi", 26: "rho",
        27: "sigma", 28: "tau", 29: "upsilon", 30: "phi",
        31: "chi", 32: "psi", 33: "omega",
        34: "epsilon", 35: "theta1", 36: "pi1", 37: "rho1",
        38: "sigma1", 39: "phi1",
        40: "arrowlefttophalf", 41: "arrowleftbothalf",
        42: "arrowrighttophalf", 43: "arrowrightbothalf",
        44: "arrowhookleft", 45: "arrowhookright",
        46: "triangleright", 47: "triangleleft",
        48: "zerooldstyle", 49: "oneoldstyle", 50: "twooldstyle",
        51: "threeoldstyle", 52: "fouroldstyle", 53: "fiveoldstyle",
        54: "sixoldstyle", 55: "sevenoldstyle", 56: "eightoldstyle",
        57: "nineoldstyle",
        58: "period", 59: "comma", 60: "less", 61: "slash",
        62: "greater", 63: "star", 64: "partialdiff",
        91: "flat", 92: "natural", 93: "sharp",
        94: "slurbelow", 95: "slurabove",
        96: "lscript", 123: "dotlessi", 124: "dotlessj",
        125: "weierstrass", 126: "vector", 127: "tie"
    ].merging(uppercaseLetterNames) { oml, _ in oml }
     .merging(lowercaseLetterNames) { oml, _ in oml }

    private static let omsGlyphNames: [Int: String] = [
        0: "minus", 1: "periodcentered", 2: "multiply",
        3: "asteriskmath", 4: "divide", 5: "diamondmath",
        6: "plusminus", 7: "minusplus", 8: "circleplus",
        9: "circleminus", 10: "circlemultiply", 11: "circledivide",
        12: "circledot", 13: "circlecopyrt", 14: "openbullet",
        15: "bullet", 16: "equivasymptotic", 17: "equivalence",
        18: "reflexsubset", 19: "reflexsuperset", 20: "lessequal",
        21: "greaterequal", 22: "precedesequal", 23: "followsequal",
        24: "similar", 25: "approxequal", 26: "propersubset",
        27: "propersuperset", 28: "lessmuch", 29: "greatermuch",
        30: "precedes", 31: "follows",
        32: "arrowleft", 33: "arrowright", 34: "arrowup",
        35: "arrowdown", 36: "arrowboth", 37: "arrownortheast",
        38: "arrowsoutheast", 39: "similarequal",
        40: "arrowdblleft", 41: "arrowdblright", 42: "arrowdblup",
        43: "arrowdbldown", 44: "arrowdblboth", 45: "arrownorthwest",
        46: "arrowsouthwest", 47: "proportional",
        48: "prime", 49: "infinity", 50: "element",
        51: "owner", 52: "triangle", 53: "triangleinv",
        54: "negationslash", 55: "mapsto", 56: "universal",
        57: "existential", 58: "logicalnot", 59: "emptyset",
        60: "Rfractur", 61: "Ifractur", 62: "latticetop",
        63: "perpendicular", 64: "aleph",
        91: "union", 92: "intersection", 93: "unionmulti",
        94: "logicaland", 95: "logicalor", 96: "turnstileleft",
        97: "turnstileright", 98: "floorleft", 99: "floorright",
        100: "ceilingleft", 101: "ceilingright",
        102: "braceleft", 103: "braceright",
        104: "angbracketleft", 105: "angbracketright",
        106: "bar", 107: "bardbl",
        108: "arrowbothv", 109: "arrowdblbothv",
        110: "backslash", 111: "wreathproduct",
        112: "radical", 113: "coproduct",
        114: "nabla", 115: "integral", 116: "unionsq",
        117: "intersectionsq", 118: "subsetsqequal", 119: "supersetsqequal",
        120: "section", 121: "dagger", 122: "daggerdbl",
        123: "paragraph", 124: "club", 125: "diamond",
        126: "heart", 127: "spade"
    ].merging(uppercaseLetterNames) { oms, _ in oms }

    private static let omxGlyphNames: [Int: String] = [
        0: "parenleftbig", 1: "parenrightbig",
        2: "bracketleftbig", 3: "bracketrightbig",
        4: "floorleftbig", 5: "floorrightbig",
        6: "ceilingleftbig", 7: "ceilingrightbig",
        8: "braceleftbig", 9: "bracerightbig",
        10: "angbracketleftbig", 11: "angbracketrightbig",
        12: "vextendsingle", 13: "vextenddouble",
        14: "slashbig", 15: "backslashbig",
        16: "parenleftBig", 17: "parenrightBig",
        18: "parenleftbigg", 19: "parenrightbigg",
        20: "bracketleftbigg", 21: "bracketrightbigg",
        22: "floorleftbigg", 23: "floorrightbigg",
        24: "ceilingleftbigg", 25: "ceilingrightbigg",
        26: "braceleftbigg", 27: "bracerightbigg",
        28: "angbracketleftbigg", 29: "angbracketrightbigg",
        30: "slashbigg", 31: "backslashbigg",
        32: "parenleftBigg", 33: "parenrightBigg",
        34: "bracketleftBigg", 35: "bracketrightBigg",
        36: "floorleftBigg", 37: "floorrightBigg",
        38: "ceilingleftBigg", 39: "ceilingrightBigg",
        40: "braceleftBigg", 41: "bracerightBigg",
        42: "angbracketleftBigg", 43: "angbracketrightBigg",
        44: "slashBigg", 45: "backslashBigg",
        46: "slashBig", 47: "backslashBig",
        48: "parenlefttp", 49: "parenrighttp",
        50: "bracketlefttp", 51: "bracketrighttp",
        52: "bracketleftbt", 53: "bracketrightbt",
        54: "bracketleftex", 55: "bracketrightex",
        56: "bracelefttp", 57: "bracerighttp",
        58: "braceleftbt", 59: "bracerightbt",
        60: "braceleftmid", 61: "bracerightmid",
        62: "braceex", 63: "arrowvertex",
        64: "parenleftbt", 65: "parenrightbt",
        66: "parenleftex", 67: "parenrightex",
        68: "angbracketleftBig", 69: "angbracketrightBig",
        70: "unionsqtext", 71: "unionsqdisplay",
        72: "contintegraltext", 73: "contintegraldisplay",
        74: "circledottext", 75: "circledotdisplay",
        76: "circleplustext", 77: "circleplusdisplay",
        78: "circlemultiplytext", 79: "circlemultiplydisplay",
        80: "summationtext", 81: "producttext",
        82: "integraltext", 83: "uniontext",
        84: "intersectiontext", 85: "unionmultitext",
        86: "logicalandtext", 87: "logicalortext",
        88: "summationdisplay", 89: "productdisplay",
        90: "integraldisplay", 91: "uniondisplay",
        92: "intersectiondisplay", 93: "unionmultidisplay",
        94: "logicalanddisplay", 95: "logicalordisplay",
        96: "coproducttext", 97: "coproductdisplay",
        98: "hatwide", 99: "hatwider",
        100: "hatwidest", 101: "tildewide",
        102: "tildewider", 103: "tildewidest",
        104: "bracketleftBig", 105: "bracketrightBig",
        106: "floorleftBig", 107: "floorrightBig",
        108: "ceilingleftBig", 109: "ceilingrightBig",
        110: "braceleftBig", 111: "bracerightBig",
        112: "radicalbig", 113: "radicalBig",
        114: "radicalbigg", 115: "radicalBigg",
        116: "radicalbt", 117: "radicalvertex",
        118: "radicaltp", 119: "arrowvertexdbl",
        120: "arrowtp", 121: "arrowbt",
        122: "bracehtipdownleft", 123: "bracehtipdownright",
        124: "bracehtipupleft", 125: "bracehtipupright",
        126: "arrowdbltp", 127: "arrowdblbt"
    ]

    private static let msamGlyphNames: [Int: String] = [
        0: "squaredot", 1: "squareplus", 2: "squaremultiply", 3: "square",
        4: "squaresolid", 5: "squaresmallsolid", 6: "diamond", 7: "diamondsolid",
        8: "clockwise", 9: "anticlockwise", 10: "harpoonleftright", 11: "harpoonrightleft",
        12: "squareminus", 13: "forces", 14: "forcesbar", 15: "satisfies",
        16: "dblarrowheadright", 17: "dblarrowheadleft", 18: "dblarrowleft", 19: "dblarrowright",
        20: "dblarrowup", 21: "dblarrowdwn", 22: "harpoonupright", 23: "harpoondownright",
        24: "harpoonupleft", 25: "harpoondownleft", 26: "arrowtailright", 27: "arrowtailleft",
        28: "arrowparrleftright", 29: "arrowparrrightleft", 30: "shiftleft", 31: "shiftright",
        32: "squiggleright", 33: "squiggleleftright", 34: "curlyleft", 35: "curlyright",
        36: "circleequal", 37: "followsorequal", 38: "greaterorsimilar", 39: "greaterorapproxeql",
        40: "multimap", 41: "therefore", 42: "because", 43: "equalsdots",
        44: "defines", 45: "precedesorequal", 46: "lessorsimilar", 47: "lessorapproxeql",
        48: "equalorless", 49: "equalorgreater", 50: "equalorprecedes", 51: "equalorfollows",
        52: "precedesorcurly", 53: "lessdblequal", 54: "lessorequalslant", 55: "lessorgreater",
        56: "primereverse", 57: "axisshort", 58: "equaldotrightleft", 59: "equaldotleftright",
        60: "followsorcurly", 61: "greaterdblequal", 62: "greaterorequalslant", 63: "greaterorless",
        64: "squareimage", 65: "squareoriginal", 66: "triangleright", 67: "triangleleft",
        68: "trianglerightequal", 69: "triangleleftequal", 70: "star", 71: "between",
        72: "triangledownsld", 73: "trianglerightsld", 74: "triangleleftsld", 75: "arrowaxisright",
        76: "arrowaxisleft", 77: "triangle", 78: "trianglesolid", 79: "triangleinv",
        80: "ringinequal", 81: "lessequalgreater", 82: "greaterlessequal", 83: "lessdbleqlgreater",
        84: "greaterdbleqlless", 85: "Yen", 86: "arrowtripleright", 87: "arrowtripleleft",
        88: "check", 89: "orunderscore", 90: "nand", 91: "perpcorrespond",
        92: "angle", 93: "measuredangle", 94: "sphericalangle", 95: "proportional",
        96: "smile", 97: "frown", 98: "subsetdbl", 99: "supersetdbl",
        100: "uniondbl", 101: "intersectiondbl", 102: "uprise", 103: "downfall",
        104: "multiopenleft", 105: "multiopenright", 106: "subsetdblequal", 107: "supersetdblequal",
        108: "difference", 109: "geomequivalent", 110: "muchless", 111: "muchgreater",
        112: "rightanglenw", 113: "rightanglene", 114: "circleR", 115: "circleS",
        116: "fork", 117: "dotplus", 118: "revsimilar", 119: "revasymptequal",
        120: "rightanglesw", 121: "rightanglese", 122: "maltesecross", 123: "complement",
        124: "intercal", 125: "circlering", 126: "circleasterisk", 127: "circleminus"
    ]

    private static let msbmGlyphNames: [Int: String] = [
        0: "lessornotequal", 1: "greaterornotequal", 2: "notlessequal", 3: "notgreaterequal",
        4: "notless", 5: "notgreater", 6: "notprecedes", 7: "notfollows",
        8: "lessornotdbleql", 9: "greaterornotdbleql", 10: "notlessorslnteql", 11: "notgreaterorslnteql",
        12: "lessnotequal", 13: "greaternotequal", 14: "notprecedesoreql", 15: "notfollowsoreql",
        16: "precedeornoteqvlnt", 17: "followornoteqvlnt", 18: "lessornotsimilar", 19: "greaterornotsimilar",
        20: "notlessdblequal", 21: "notgreaterdblequal", 22: "precedenotslnteql", 23: "follownotslnteql",
        24: "precedenotdbleqv", 25: "follownotdbleqv", 26: "lessnotdblequal", 27: "greaternotdblequal",
        28: "notsimilar", 29: "notapproxequal", 30: "upslope", 31: "downslope",
        32: "notsubsetoreql", 33: "notsupersetoreql", 34: "notsubsetordbleql", 35: "notsupersetordbleql",
        36: "subsetornotdbleql", 37: "supersetornotdbleql", 38: "subsetornoteql", 39: "supersetornoteql",
        40: "subsetnoteql", 41: "supersetnoteql", 42: "notsubseteql", 43: "notsuperseteql",
        44: "notparallel", 45: "notbar", 46: "notshortbar", 47: "notshortparallel",
        48: "notturnstile", 49: "notforces", 50: "notsatisfies", 51: "notforcesextra",
        52: "nottriangeqlright", 53: "nottriangeqlleft", 54: "nottriangleleft", 55: "nottriangleright",
        56: "notarrowleft", 57: "notarrowright", 58: "notdblarrowleft", 59: "notdblarrowright",
        60: "notdblarrowboth", 61: "notarrowboth", 62: "dividemultiply", 63: "emptyset",
        64: "notexistential", 65: "A", 66: "B", 67: "C",
        68: "D", 69: "E", 70: "F", 71: "G",
        72: "H", 73: "I", 74: "J", 75: "K",
        76: "L", 77: "M", 78: "N", 79: "OO",
        80: "P", 81: "Q", 82: "R", 83: "S",
        84: "T", 85: "U", 86: "V", 87: "WW",
        88: "X", 89: "Y", 90: "Z", 91: "hatwide",
        92: "hatwider", 93: "tildewide", 94: "tildewider", 96: "Finv",
        97: "Gmir", 102: "Omegainv", 103: "eth", 104: "equalorsimilar",
        105: "beth", 106: "gimel", 107: "daleth", 108: "lessdot",
        109: "greaterdot", 110: "multicloseleft", 111: "multicloseright", 112: "barshort",
        113: "parallelshort", 114: "integerdivide", 115: "similar", 116: "approxequal",
        117: "approxorequal", 118: "followsorequal", 119: "precedesorequal", 120: "archleftdown",
        121: "archrightdown", 122: "Digamma", 123: "kappa", 124: "k",
        125: "planckover2pi", 126: "planckover2pi1", 127: "epsiloninv"
    ]

    private static let t1GlyphNames: [Int: String] = [
        0: "grave", 1: "acute", 2: "circumflex", 3: "tilde",
        4: "dieresis", 5: "hungarumlaut", 6: "ring", 7: "caron",
        8: "breve", 9: "macron", 10: "dotaccent", 11: "cedilla",
        12: "ogonek", 13: "quotesinglbase", 14: "guilsinglleft",
        15: "guilsinglright",
        16: "quotedblleft", 17: "quotedblright", 18: "quotedblbase",
        19: "guillemotleft", 20: "guillemotright",
        21: "endash", 22: "emdash", 23: "compoundwordmark",
        24: "dotlessi", 25: "dotlessj",
        26: "ff", 27: "fi", 28: "fl", 29: "ffi", 30: "ffl",
        31: "visiblespace",
        127: "hyphenchar",
        128: "Aogonek", 129: "Eogonek", 130: "Zacute", 131: "Dcaron",
        132: "Ecaron", 133: "Lacute", 134: "Lcaron", 135: "Lslash",
        136: "Nacute", 137: "Ncaron", 138: "Eng", 139: "Ohungarumlaut",
        140: "Racute", 141: "Rcaron", 142: "Sacute", 143: "Scaron",
        144: "Scedilla", 145: "Tcaron", 146: "Tcedilla", 147: "Uring",
        148: "Uhungarumlaut", 149: "Ydieresis", 150: "Zcaron", 151: "IJ",
        152: "Idotaccent", 153: "Dbar", 154: "section", 155: "aogonek",
        156: "eogonek", 157: "zacute", 158: "dcaron", 159: "ecaron",
        160: "lacute", 161: "lcaron", 162: "lslash", 163: "nacute",
        164: "ncaron", 165: "eng", 166: "ohungarumlaut", 167: "racute",
        168: "rcaron", 169: "sacute", 170: "scaron", 171: "scedilla",
        172: "tcaron", 173: "tcedilla", 174: "uring", 175: "uhungarumlaut",
        176: "ydieresis", 177: "zcaron", 178: "ij", 179: "exclamdown",
        180: "questiondown", 181: "sterling", 182: "currency", 183: "Euro",
        184: "brokenbar", 185: "ordmasculine", 186: "ordfeminine",
        187: "copyright", 188: "registered", 189: "perthousand",
        190: "mu", 191: "paragraph",
        192: "Agrave", 193: "Aacute", 194: "Acircumflex", 195: "Atilde",
        196: "Adieresis", 197: "Aring", 198: "AE", 199: "Ccedilla",
        200: "Egrave", 201: "Eacute", 202: "Ecircumflex", 203: "Edieresis",
        204: "Igrave", 205: "Iacute", 206: "Icircumflex", 207: "Idieresis",
        208: "Eth", 209: "Ntilde", 210: "Ograve", 211: "Oacute",
        212: "Ocircumflex", 213: "Otilde", 214: "Odieresis", 215: "OE",
        216: "Oslash", 217: "Ugrave", 218: "Uacute", 219: "Ucircumflex",
        220: "Udieresis", 221: "Yacute", 222: "Thorn", 223: "Germandbls",
        224: "agrave", 225: "aacute", 226: "acircumflex", 227: "atilde",
        228: "adieresis", 229: "aring", 230: "ae", 231: "ccedilla",
        232: "egrave", 233: "eacute", 234: "ecircumflex", 235: "edieresis",
        236: "igrave", 237: "iacute", 238: "icircumflex", 239: "idieresis",
        240: "eth", 241: "ntilde", 242: "ograve", 243: "oacute",
        244: "ocircumflex", 245: "otilde", 246: "odieresis", 247: "oe",
        248: "oslash", 249: "ugrave", 250: "uacute", 251: "ucircumflex",
        252: "udieresis", 253: "yacute", 254: "thorn", 255: "germandbls"
    ].merging(standardGlyphNames) { t1, _ in t1 }

    private static let uppercaseLetterNames: [Int: String] = [
        65: "A", 66: "B", 67: "C", 68: "D", 69: "E", 70: "F",
        71: "G", 72: "H", 73: "I", 74: "J", 75: "K", 76: "L",
        77: "M", 78: "N", 79: "O", 80: "P", 81: "Q", 82: "R",
        83: "S", 84: "T", 85: "U", 86: "V", 87: "W", 88: "X",
        89: "Y", 90: "Z"
    ]

    private static let lowercaseLetterNames: [Int: String] = [
        97: "a", 98: "b", 99: "c", 100: "d", 101: "e", 102: "f",
        103: "g", 104: "h", 105: "i", 106: "j", 107: "k", 108: "l",
        109: "m", 110: "n", 111: "o", 112: "p", 113: "q", 114: "r",
        115: "s", 116: "t", 117: "u", 118: "v", 119: "w", 120: "x",
        121: "y", 122: "z"
    ]

    private static let standardGlyphNames: [Int: String] = [
        32: "space", 33: "exclam", 34: "quotedbl", 35: "numbersign",
        36: "dollar", 37: "percent", 38: "ampersand", 39: "quotesingle",
        40: "parenleft", 41: "parenright", 42: "asterisk", 43: "plus",
        44: "comma", 45: "hyphen", 46: "period", 47: "slash",
        48: "zero", 49: "one", 50: "two", 51: "three",
        52: "four", 53: "five", 54: "six", 55: "seven",
        56: "eight", 57: "nine",
        58: "colon", 59: "semicolon", 60: "less", 61: "equal",
        62: "greater", 63: "question", 64: "at",
        91: "bracketleft", 92: "backslash", 93: "bracketright",
        94: "asciicircum", 95: "underscore", 96: "quoteleft",
        123: "braceleft", 124: "bar", 125: "braceright",
        126: "asciitilde"
    ].merging(uppercaseLetterNames) { std, _ in std }
     .merging(lowercaseLetterNames) { std, _ in std }
}
