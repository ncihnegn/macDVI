import Foundation

final class DVIParser {
    private let url: URL
    private let data: Data
    private let metricProvider: TFMFontMetricProvider
    private let pageOriginOffsetPoints = 72.0
    private let defaultMediaSize = CGSize(width: 612, height: 792)

    private var preamble: DVIPreamble?
    private var fonts: [Int: DVIFontDefinition] = [:]
    private var warnings: [String] = []

    init(url: URL) throws {
        self.url = url
        self.data = try Data(contentsOf: url)
        self.metricProvider = TFMFontMetricProvider(documentURL: url)
        if data.isEmpty {
            throw DVIError.emptyFile
        }
    }

    func parse() throws -> DVIDocument {
        try collectPreambleAndFonts()
        guard let preamble else {
            throw DVIError.invalidPreamble
        }
        let pages = try parsePages(preamble: preamble)
        return DVIDocument(url: url, preamble: preamble, fonts: fonts, pages: pages, warnings: warnings)
    }

    private func collectPreambleAndFonts() throws {
        var reader = DVIByteReader(data: data)
        let firstOpcode = try reader.readByte()
        guard firstOpcode == 247 else {
            throw DVIError.invalidPreamble
        }

        preamble = try readPreamble(reader: &reader)
        if let preamble, preamble.id != 2 {
            warnings.append("DVI identifier \(preamble.id) is not the standard TeX DVI id 2.")
        }

        while !reader.isAtEnd {
            let opcodeOffset = reader.offset
            let opcode = try reader.readByte()
            switch opcode {
            case 0...127:
                continue
            case 128...131:
                try reader.skip(Int(opcode - 127))
            case 132:
                try reader.skip(8)
            case 133...136:
                try reader.skip(Int(opcode - 132))
            case 137:
                try reader.skip(8)
            case 138, 140...142, 147, 152, 161:
                continue
            case 139:
                try reader.skip(44)
            case 143...146:
                try reader.skip(Int(opcode - 142))
            case 148...151:
                try reader.skip(Int(opcode - 147))
            case 153...156:
                try reader.skip(Int(opcode - 152))
            case 157...160:
                try reader.skip(Int(opcode - 156))
            case 162...165:
                try reader.skip(Int(opcode - 161))
            case 166...170:
                try reader.skip(Int(opcode - 165))
            case 171...234:
                continue
            case 235...238:
                try reader.skip(Int(opcode - 234))
            case 239...242:
                let length = try reader.readUnsigned(Int(opcode - 238))
                try reader.skip(Int(length))
            case 243...246:
                let definition = try readFontDefinition(opcode: opcode, reader: &reader)
                fonts[definition.number] = definition
            case 247:
                throw DVIError.malformed("duplicate preamble at byte offset \(opcodeOffset)")
            case 248:
                try reader.skipPostambleHeader()
            case 249:
                return
            case 250...255:
                continue
            default:
                throw DVIError.unsupportedOpcode(opcode, offset: opcodeOffset)
            }
        }
    }

    private func parsePages(preamble: DVIPreamble) throws -> [DVIPage] {
        var reader = DVIByteReader(data: data)
        var pages: [DVIPage] = []
        var pageIndex = 0
        var currentPage: PageBuilder?
        var state = DVIState()
        let pointsPerDVIUnit = preamble.pointsPerDVIUnit

        while !reader.isAtEnd {
            let opcodeOffset = reader.offset
            let opcode = try reader.readByte()

            switch opcode {
            case 0...127:
                try setCharacter(Int(opcode), moveAfterSet: true, state: &state, page: &currentPage, pointsPerDVIUnit: pointsPerDVIUnit)
            case 128...131:
                let code = Int(try reader.readUnsigned(Int(opcode - 127)))
                try setCharacter(code, moveAfterSet: true, state: &state, page: &currentPage, pointsPerDVIUnit: pointsPerDVIUnit)
            case 132:
                let height = try reader.readSigned(4)
                let width = try reader.readSigned(4)
                putRule(height: height, width: width, moveAfterSet: true, state: &state, page: &currentPage, pointsPerDVIUnit: pointsPerDVIUnit)
            case 133...136:
                let code = Int(try reader.readUnsigned(Int(opcode - 132)))
                try setCharacter(code, moveAfterSet: false, state: &state, page: &currentPage, pointsPerDVIUnit: pointsPerDVIUnit)
            case 137:
                let height = try reader.readSigned(4)
                let width = try reader.readSigned(4)
                putRule(height: height, width: width, moveAfterSet: false, state: &state, page: &currentPage, pointsPerDVIUnit: pointsPerDVIUnit)
            case 138:
                continue
            case 139:
                let counters = try (0..<10).map { _ in try reader.readSigned(4) }
                _ = try reader.readSigned(4)
                state = DVIState()
                currentPage = PageBuilder(number: pageIndex + 1, counters: counters)
                pageIndex += 1
            case 140:
                if let builder = currentPage {
                    pages.append(builder.finish(defaultMediaSize: defaultMediaSize))
                }
                currentPage = nil
            case 141:
                state.stack.append(DVIStackFrame(h: state.h, v: state.v, w: state.w, x: state.x, y: state.y, z: state.z))
            case 142:
                guard let frame = state.stack.popLast() else {
                    throw DVIError.malformed("pop with empty DVI stack at byte offset \(opcodeOffset)")
                }
                state.h = frame.h
                state.v = frame.v
                state.w = frame.w
                state.x = frame.x
                state.y = frame.y
                state.z = frame.z
            case 143...146:
                state.h += try reader.readSigned(Int(opcode - 142))
            case 147:
                state.h += state.w
            case 148...151:
                let value = try reader.readSigned(Int(opcode - 147))
                state.w = value
                state.h += value
            case 152:
                state.h += state.x
            case 153...156:
                let value = try reader.readSigned(Int(opcode - 152))
                state.x = value
                state.h += value
            case 157...160:
                state.v += try reader.readSigned(Int(opcode - 156))
            case 161:
                state.v += state.y
            case 162...165:
                let value = try reader.readSigned(Int(opcode - 161))
                state.y = value
                state.v += value
            case 166:
                state.v += state.z
            case 167...170:
                let value = try reader.readSigned(Int(opcode - 165))
                state.z = value
                state.v += value
            case 171...234:
                state.currentFontNumber = Int(opcode - 171)
            case 235...238:
                state.currentFontNumber = Int(try reader.readUnsigned(Int(opcode - 234)))
            case 239...242:
                let length = Int(try reader.readUnsigned(Int(opcode - 238)))
                let bytes = try reader.readBytes(length)
                if let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .ascii) {
                    if var page = currentPage {
                        page.add(.special(DVISpecial(
                            x: xPoint(state.h, pointsPerDVIUnit),
                            y: yPoint(state.v, pointsPerDVIUnit),
                            text: text
                        )))
                        currentPage = page
                    }
                    applySpecial(text, state: &state, at: opcodeOffset)
                }
            case 243...246:
                let definition = try readFontDefinition(opcode: opcode, reader: &reader)
                fonts[definition.number] = definition
            case 247:
                _ = try readPreamble(reader: &reader)
            case 248:
                return pages
            case 249:
                return pages
            case 250...255:
                continue
            default:
                throw DVIError.unsupportedOpcode(opcode, offset: opcodeOffset)
            }
        }

        return pages
    }

    private func setCharacter(
        _ characterCode: Int,
        moveAfterSet: Bool,
        state: inout DVIState,
        page: inout PageBuilder?,
        pointsPerDVIUnit: Double
    ) throws {
        guard let fontNumber = state.currentFontNumber else {
            warnings.append("Character \(characterCode) appeared before a font was selected.")
            return
        }

        let advanceDVI = widthDVIUnits(characterCode: characterCode, fontNumber: fontNumber, pointsPerDVIUnit: pointsPerDVIUnit)
        if page != nil {
            let fontSize = fontSizePoints(fontNumber: fontNumber, pointsPerDVIUnit: pointsPerDVIUnit)
            page?.add(.glyph(DVIGlyph(
                fontNumber: fontNumber,
                characterCode: characterCode,
                x: xPoint(state.h, pointsPerDVIUnit),
                baselineY: yPoint(state.v, pointsPerDVIUnit),
                advance: Double(advanceDVI) * pointsPerDVIUnit,
                fontSize: fontSize,
                color: state.currentColor
            )))
        }

        if moveAfterSet {
            state.h += advanceDVI
        }
    }

    private func putRule(
        height: Int64,
        width: Int64,
        moveAfterSet: Bool,
        state: inout DVIState,
        page: inout PageBuilder?,
        pointsPerDVIUnit: Double
    ) {
        if height > 0, width > 0, page != nil {
            let widthPoints = Double(width) * pointsPerDVIUnit
            let heightPoints = Double(height) * pointsPerDVIUnit
            page?.add(.rule(DVIRule(
                x: xPoint(state.h, pointsPerDVIUnit),
                y: yPoint(state.v - height, pointsPerDVIUnit),
                width: widthPoints,
                height: heightPoints,
                color: state.currentColor
            )))
        }
        if moveAfterSet {
            state.h += width
        }
    }

    private func widthDVIUnits(characterCode: Int, fontNumber: Int, pointsPerDVIUnit: Double) -> Int64 {
        guard let font = fonts[fontNumber] else {
            return fallbackWidthDVIUnits(characterCode: characterCode, scaledSize: Int64(10.0 / pointsPerDVIUnit))
        }

        if let width = metricProvider.metric(for: font.name)?.widthDVIUnits(for: characterCode, scaledSize: font.scaledSize) {
            return width
        }
        return fallbackWidthDVIUnits(characterCode: characterCode, scaledSize: font.scaledSize)
    }

    private func fallbackWidthDVIUnits(characterCode: Int, scaledSize: Int64) -> Int64 {
        let scalar = UnicodeScalar(characterCode)
        let fraction: Double
        if characterCode == 32 {
            fraction = 0.333
        } else if let scalar, CharacterSet(charactersIn: "il.,'`!|:;").contains(scalar) {
            fraction = 0.25
        } else if let scalar, CharacterSet(charactersIn: "mwMW@#%").contains(scalar) {
            fraction = 0.78
        } else if let scalar, CharacterSet.uppercaseLetters.contains(scalar) {
            fraction = 0.67
        } else {
            fraction = 0.5
        }
        return Int64((Double(scaledSize) * fraction).rounded())
    }

    private func fontSizePoints(fontNumber: Int, pointsPerDVIUnit: Double) -> Double {
        guard let font = fonts[fontNumber] else { return 10.0 }
        return max(1.0, Double(font.scaledSize) * pointsPerDVIUnit)
    }

    private func xPoint(_ dviUnits: Int64, _ pointsPerDVIUnit: Double) -> Double {
        pageOriginOffsetPoints + Double(dviUnits) * pointsPerDVIUnit
    }

    private func yPoint(_ dviUnits: Int64, _ pointsPerDVIUnit: Double) -> Double {
        pageOriginOffsetPoints + Double(dviUnits) * pointsPerDVIUnit
    }

    private func applySpecial(_ text: String, state: inout DVIState, at offset: Int) {
        guard let command = DVISpecialParser.colorCommand(from: text) else {
            return
        }

        switch command {
        case .push(let color):
            state.colorStack.append(state.currentColor)
            if let color {
                state.currentColor = color
            }
        case .pop:
            guard let previous = state.colorStack.popLast() else {
                warnings.append("Color pop appeared with an empty color stack at byte offset \(offset).")
                return
            }
            state.currentColor = previous
        }
    }

    private func readPreamble(reader: inout DVIByteReader) throws -> DVIPreamble {
        let id = try reader.readByte()
        let numerator = Int64(try reader.readUnsigned(4))
        let denominator = Int64(try reader.readUnsigned(4))
        let magnification = Int64(try reader.readUnsigned(4))
        let commentLength = Int(try reader.readUnsigned(1))
        let commentBytes = try reader.readBytes(commentLength)
        return DVIPreamble(
            id: id,
            numerator: numerator,
            denominator: denominator,
            magnification: magnification,
            comment: String(data: commentBytes, encoding: .utf8)
                ?? String(data: commentBytes, encoding: .ascii)
                ?? ""
        )
    }

    private func readFontDefinition(opcode: UInt8, reader: inout DVIByteReader) throws -> DVIFontDefinition {
        let number = Int(try reader.readUnsigned(Int(opcode - 242)))
        let checksum = UInt32(try reader.readUnsigned(4))
        let scaledSize = Int64(try reader.readUnsigned(4))
        let designSize = Int64(try reader.readUnsigned(4))
        let areaLength = Int(try reader.readUnsigned(1))
        let nameLength = Int(try reader.readUnsigned(1))
        let areaBytes = try reader.readBytes(areaLength)
        let nameBytes = try reader.readBytes(nameLength)
        return DVIFontDefinition(
            number: number,
            checksum: checksum,
            scaledSize: scaledSize,
            designSize: designSize,
            area: String(data: areaBytes, encoding: .utf8) ?? String(data: areaBytes, encoding: .ascii) ?? "",
            name: String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .ascii) ?? ""
        )
    }
}

private struct DVIState {
    var h: Int64 = 0
    var v: Int64 = 0
    var w: Int64 = 0
    var x: Int64 = 0
    var y: Int64 = 0
    var z: Int64 = 0
    var currentFontNumber: Int?
    var currentColor: DVIColor = .black
    var colorStack: [DVIColor] = []
    var stack: [DVIStackFrame] = []
}

private struct DVIStackFrame {
    let h: Int64
    let v: Int64
    let w: Int64
    let x: Int64
    let y: Int64
    let z: Int64
}

private struct PageBuilder {
    let number: Int
    let counters: [Int64]
    private(set) var items: [DVIPageItem] = []

    mutating func add(_ item: DVIPageItem) {
        items.append(item)
    }

    func finish(defaultMediaSize: CGSize) -> DVIPage {
        let mediaSize = items.compactMap { item -> CGSize? in
            guard case .special(let special) = item else { return nil }
            return DVISpecialParser.mediaSize(from: special.text)
        }.last ?? defaultMediaSize

        var maxX = mediaSize.width
        var maxY = mediaSize.height
        for item in items {
            switch item {
            case .glyph(let glyph):
                maxX = max(maxX, glyph.x + glyph.advance + 72)
                maxY = max(maxY, glyph.baselineY + glyph.fontSize + 72)
            case .rule(let rule):
                maxX = max(maxX, rule.x + rule.width + 72)
                maxY = max(maxY, rule.y + rule.height + 72)
            case .special(let special):
                maxX = max(maxX, special.x + 72)
                maxY = max(maxY, special.y + 72)
            }
        }
        return DVIPage(number: number, counters: counters, items: items, mediaBox: CGSize(width: maxX, height: maxY))
    }
}

private enum DVISpecialParser {
    enum ColorCommand {
        case push(DVIColor?)
        case pop
    }

    static func colorCommand(from text: String) -> ColorCommand? {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2, tokens[0].lowercased() == "color" else {
            return nil
        }

        switch tokens[1].lowercased() {
        case "push":
            let color = parseColor(tokens.dropFirst(2))
            return .push(color)
        case "pop":
            return .pop
        default:
            return nil
        }
    }

    static func mediaSize(from text: String) -> CGSize? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("papersize") else {
            return nil
        }

        var value = String(trimmed.dropFirst("papersize".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("=") {
            value.removeFirst()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = value.split(separator: ",", maxSplits: 1)
        guard parts.count == 2,
              let width = parseDimension(String(parts[0])),
              let height = parseDimension(String(parts[1])),
              width > 0,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func parseColor(_ tokens: ArraySlice<Substring>) -> DVIColor? {
        guard let first = tokens.first?.lowercased() else {
            return nil
        }

        switch first {
        case "rgb":
            guard tokens.count >= 4,
                  let red = Double(tokens[tokens.startIndex + 1]),
                  let green = Double(tokens[tokens.startIndex + 2]),
                  let blue = Double(tokens[tokens.startIndex + 3]) else {
                return nil
            }
            return DVIColor(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: 1)
        case "gray", "grey":
            guard tokens.count >= 2,
                  let value = Double(tokens[tokens.startIndex + 1]) else {
                return nil
            }
            let component = clamp(value)
            return DVIColor(red: component, green: component, blue: component, alpha: 1)
        case "cmyk":
            guard tokens.count >= 5,
                  let cyan = Double(tokens[tokens.startIndex + 1]),
                  let magenta = Double(tokens[tokens.startIndex + 2]),
                  let yellow = Double(tokens[tokens.startIndex + 3]),
                  let black = Double(tokens[tokens.startIndex + 4]) else {
                return nil
            }
            return DVIColor(
                red: clamp(1 - min(1, cyan + black)),
                green: clamp(1 - min(1, magenta + black)),
                blue: clamp(1 - min(1, yellow + black)),
                alpha: 1
            )
        default:
            return namedColors[first]
        }
    }

    private static func parseDimension(_ text: String) -> Double? {
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = .whitespacesAndNewlines
        guard let value = scanner.scanDouble() else {
            return nil
        }

        let unit = String(text[scanner.currentIndex...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch unit {
        case "", "bp", "px":
            return value
        case "pt":
            return value * 72.0 / 72.27
        case "in":
            return value * 72.0
        case "cm":
            return value * 72.0 / 2.54
        case "mm":
            return value * 72.0 / 25.4
        default:
            return nil
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static let namedColors: [String: DVIColor] = [
        "black": .black,
        "white": DVIColor(red: 1, green: 1, blue: 1, alpha: 1),
        "red": DVIColor(red: 1, green: 0, blue: 0, alpha: 1),
        "green": DVIColor(red: 0, green: 1, blue: 0, alpha: 1),
        "blue": DVIColor(red: 0, green: 0, blue: 1, alpha: 1),
        "cyan": DVIColor(red: 0, green: 1, blue: 1, alpha: 1),
        "magenta": DVIColor(red: 1, green: 0, blue: 1, alpha: 1),
        "yellow": DVIColor(red: 1, green: 1, blue: 0, alpha: 1),
        "gray": DVIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
        "grey": DVIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
        "orange": DVIColor(red: 1, green: 0.5, blue: 0, alpha: 1),
        "purple": DVIColor(red: 0.5, green: 0, blue: 0.5, alpha: 1),
        "brown": DVIColor(red: 0.59, green: 0.29, blue: 0, alpha: 1)
    ]
}

private extension DVIByteReader {
    mutating func skipPostambleHeader() throws {
        try skip(4 + 4 + 4 + 4 + 4 + 4 + 2 + 2)
    }
}
