import Foundation

final class DVIParser {
    private let url: URL
    private let data: Data
    private let metricProvider: TFMFontMetricProvider
    private let virtualFontProvider: VirtualFontProvider
    private let pageOriginOffsetPoints = 72.0
    private let defaultMediaSize = CGSize(width: 612, height: 792)

    private var preamble: DVIPreamble?
    private var fonts: [Int: DVIFontDefinition] = [:]
    private var warnings: [String] = []
    private var warnedMissingMetricFonts: Set<Int> = []
    private var warnedChecksumFonts: Set<Int> = []
    private var virtualFontMappings: [Int: [Int: Int]] = [:]
    private var nextSyntheticFontNumber: Int = 1_000_000
    private var virtualFontExpansionDepth = 0
    private let maxVirtualFontExpansionDepth = 16

    init(url: URL) throws {
        self.url = url
        self.data = try Data(contentsOf: url)
        self.metricProvider = TFMFontMetricProvider(documentURL: url)
        self.virtualFontProvider = VirtualFontProvider(documentURL: url)
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
        if let preamble, preamble.id != 2 && preamble.id != 7 {
            warnings.append("DVI identifier \(preamble.id) is not the standard TeX DVI id 2 or XDV id 7.")
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
            case 250...251:
                continue
            case 252:
                let nativeDef = try readXDVDefineNativeFont(reader: &reader)
                fonts[nativeDef.number] = nativeDef
            case 253:
                try skipXDVGlyphArray(reader: &reader)
            case 254:
                try skipXDVPicFile(reader: &reader)
            case 255:
                let nativeDef = try readXDVDefineNativeFont(reader: &reader)
                fonts[nativeDef.number] = nativeDef
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
            case 250...251:
                continue
            case 252:
                let nativeDef = try readXDVDefineNativeFont(reader: &reader)
                fonts[nativeDef.number] = nativeDef
            case 253:
                try parseXDVGlyphArray(reader: &reader, state: &state, page: &currentPage, pointsPerDVIUnit: pointsPerDVIUnit)
            case 254:
                try parseXDVPicFile(reader: &reader, state: &state, page: &currentPage, pointsPerDVIUnit: pointsPerDVIUnit)
            case 255:
                let nativeDef = try readXDVDefineNativeFont(reader: &reader)
                fonts[nativeDef.number] = nativeDef
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

        if let definition = fonts[fontNumber],
           let virtualFont = virtualFontProvider.virtualFont(for: definition),
           let packet = virtualFont.packets[characterCode] {
            try expandVirtualPacket(
                packet: packet,
                outerFontNumber: fontNumber,
                outerFont: definition,
                virtualFont: virtualFont,
                state: &state,
                page: &page,
                pointsPerDVIUnit: pointsPerDVIUnit
            )
            if moveAfterSet {
                state.h += scaleVFWidth(packet.widthFix, outerScaledSize: definition.scaledSize)
            }
            return
        }

        let metric = characterMetricDVIUnits(
            characterCode: characterCode,
            fontNumber: fontNumber,
            pointsPerDVIUnit: pointsPerDVIUnit
        )
        if page != nil {
            let fontSize = fontSizePoints(fontNumber: fontNumber, pointsPerDVIUnit: pointsPerDVIUnit)
            page?.add(.glyph(DVIGlyph(
                fontNumber: fontNumber,
                characterCode: characterCode,
                x: xPoint(state.h, pointsPerDVIUnit),
                baselineY: yPoint(state.v, pointsPerDVIUnit),
                advance: Double(metric.widthDVIUnits) * pointsPerDVIUnit,
                height: Double(metric.heightDVIUnits) * pointsPerDVIUnit,
                depth: Double(metric.depthDVIUnits) * pointsPerDVIUnit,
                italicCorrection: Double(metric.italicCorrectionDVIUnits) * pointsPerDVIUnit,
                fontSize: fontSize,
                color: state.currentColor
            )))
        }

        if moveAfterSet {
            state.h += metric.widthDVIUnits
        }
    }

    private func expandVirtualPacket(
        packet: VFCharacterPacket,
        outerFontNumber: Int,
        outerFont: DVIFontDefinition,
        virtualFont: VirtualFont,
        state: inout DVIState,
        page: inout PageBuilder?,
        pointsPerDVIUnit: Double
    ) throws {
        guard virtualFontExpansionDepth < maxVirtualFontExpansionDepth else {
            warnings.append("Virtual font expansion depth limit reached for \(outerFont.texName).")
            return
        }
        virtualFontExpansionDepth += 1
        defer { virtualFontExpansionDepth -= 1 }

        let mapping = synthesizeLocalFontMapping(
            for: outerFontNumber,
            outerFont: outerFont,
            virtualFont: virtualFont
        )

        var localState = DVIState()
        localState.h = state.h
        localState.v = state.v
        localState.currentColor = state.currentColor
        localState.colorStack = state.colorStack
        if let firstLocal = virtualFont.localFonts.first,
           let outer = mapping[firstLocal.localNumber] {
            localState.currentFontNumber = outer
        } else {
            localState.currentFontNumber = outerFontNumber
        }

        var packetReader = DVIByteReader(data: packet.dviCommands)
        try runVFSubroutine(
            reader: &packetReader,
            state: &localState,
            page: &page,
            pointsPerDVIUnit: pointsPerDVIUnit,
            mapping: mapping
        )
    }

    private func runVFSubroutine(
        reader: inout DVIByteReader,
        state: inout DVIState,
        page: inout PageBuilder?,
        pointsPerDVIUnit: Double,
        mapping: [Int: Int]
    ) throws {
        while !reader.isAtEnd {
            let opcode = try reader.readByte()
            switch opcode {
            case 0...127:
                try setCharacter(Int(opcode), moveAfterSet: true, state: &state, page: &page, pointsPerDVIUnit: pointsPerDVIUnit)
            case 128...131:
                let code = Int(try reader.readUnsigned(Int(opcode - 127)))
                try setCharacter(code, moveAfterSet: true, state: &state, page: &page, pointsPerDVIUnit: pointsPerDVIUnit)
            case 132:
                let height = try reader.readSigned(4)
                let width = try reader.readSigned(4)
                putRule(height: height, width: width, moveAfterSet: true, state: &state, page: &page, pointsPerDVIUnit: pointsPerDVIUnit)
            case 133...136:
                let code = Int(try reader.readUnsigned(Int(opcode - 132)))
                try setCharacter(code, moveAfterSet: false, state: &state, page: &page, pointsPerDVIUnit: pointsPerDVIUnit)
            case 137:
                let height = try reader.readSigned(4)
                let width = try reader.readSigned(4)
                putRule(height: height, width: width, moveAfterSet: false, state: &state, page: &page, pointsPerDVIUnit: pointsPerDVIUnit)
            case 138:
                continue
            case 141:
                state.stack.append(DVIStackFrame(h: state.h, v: state.v, w: state.w, x: state.x, y: state.y, z: state.z))
            case 142:
                guard let frame = state.stack.popLast() else {
                    throw DVIError.malformed("VF: pop with empty stack")
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
                let local = Int(opcode - 171)
                state.currentFontNumber = mapping[local]
            case 235...238:
                let local = Int(try reader.readUnsigned(Int(opcode - 234)))
                state.currentFontNumber = mapping[local]
            case 239...242:
                let length = Int(try reader.readUnsigned(Int(opcode - 238)))
                _ = try reader.readBytes(length)
            default:
                throw DVIError.malformed("VF: unsupported opcode \(opcode)")
            }
        }
    }

    private func synthesizeLocalFontMapping(
        for outerFontNumber: Int,
        outerFont: DVIFontDefinition,
        virtualFont: VirtualFont
    ) -> [Int: Int] {
        if let cached = virtualFontMappings[outerFontNumber] {
            return cached
        }

        var mapping: [Int: Int] = [:]
        let outerScaled = outerFont.scaledSize
        let vfDesign = virtualFont.designSize > 0 ? virtualFont.designSize : (1 << 20)

        for local in virtualFont.localFonts {
            let scaled = scaleLocalFontSize(
                localScaled: local.scaledSize,
                outerScaled: outerScaled,
                vfDesignSize: vfDesign
            )
            let synthesizedNumber = nextSyntheticFontNumber
            nextSyntheticFontNumber += 1
            let definition = DVIFontDefinition(
                number: synthesizedNumber,
                checksum: local.checksum,
                scaledSize: scaled,
                designSize: local.designSize,
                area: local.area,
                name: local.name
            )
            fonts[synthesizedNumber] = definition
            mapping[local.localNumber] = synthesizedNumber
        }

        virtualFontMappings[outerFontNumber] = mapping
        return mapping
    }

    private func scaleLocalFontSize(
        localScaled: Int64,
        outerScaled: Int64,
        vfDesignSize: Int64
    ) -> Int64 {
        guard vfDesignSize > 0 else { return localScaled }
        let product = Double(localScaled) * Double(outerScaled) / Double(vfDesignSize)
        return Int64(product.rounded())
    }

    private func scaleVFWidth(_ widthFix: Int64, outerScaledSize: Int64) -> Int64 {
        let value = Double(widthFix) * Double(outerScaledSize) / Double(1 << 20)
        return Int64(value.rounded())
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

    private func characterMetricDVIUnits(
        characterCode: Int,
        fontNumber: Int,
        pointsPerDVIUnit: Double
    ) -> TFMCharacterMetric {
        guard let font = fonts[fontNumber] else {
            return fallbackCharacterMetricDVIUnits(
                characterCode: characterCode,
                scaledSize: Int64(10.0 / pointsPerDVIUnit)
            )
        }

        if let fontMetric = metricProvider.metric(for: font) {
            validateChecksum(font: font, metric: fontMetric)
            if let metric = fontMetric.characterMetric(for: characterCode, scaledSize: font.scaledSize) {
                return metric
            }
            return fallbackCharacterMetricDVIUnits(characterCode: characterCode, scaledSize: font.scaledSize)
        }

        if !warnedMissingMetricFonts.contains(fontNumber) {
            warnings.append("TFM metrics for font \(font.texName) were not found; using estimated metrics.")
            warnedMissingMetricFonts.insert(fontNumber)
        }
        return fallbackCharacterMetricDVIUnits(characterCode: characterCode, scaledSize: font.scaledSize)
    }

    private func validateChecksum(font: DVIFontDefinition, metric: TFMFontMetric) {
        guard !warnedChecksumFonts.contains(font.number) else {
            return
        }
        warnedChecksumFonts.insert(font.number)

        guard font.checksum != 0,
              metric.checksum != 0,
              font.checksum != metric.checksum else {
            return
        }
        warnings.append("TFM checksum for font \(font.texName) does not match the DVI font definition.")
    }

    private func fallbackCharacterMetricDVIUnits(characterCode: Int, scaledSize: Int64) -> TFMCharacterMetric {
        let heightFraction: Double
        let depthFraction: Double
        if characterCode == 32 {
            heightFraction = 0
            depthFraction = 0
        } else if let scalar = UnicodeScalar(characterCode),
                  CharacterSet(charactersIn: "gjpqyQ,;_").contains(scalar) {
            heightFraction = 0.7
            depthFraction = 0.2
        } else {
            heightFraction = 0.7
            depthFraction = 0
        }

        return TFMCharacterMetric(
            widthDVIUnits: fallbackWidthDVIUnits(characterCode: characterCode, scaledSize: scaledSize),
            heightDVIUnits: Int64((Double(scaledSize) * heightFraction).rounded()),
            depthDVIUnits: Int64((Double(scaledSize) * depthFraction).rounded()),
            italicCorrectionDVIUnits: 0
        )
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

    // MARK: - XDV opcode helpers

    /// Opcode 253: XDV_GLYPH_ARRAY — 4 bytes width + 2 bytes glyph count (n) + n×(4+4) bytes positions + n×2 bytes glyph IDs
    private func skipXDVGlyphArray(reader: inout DVIByteReader) throws {
        try reader.skip(4) // width (Fixed 26.6 / DVI units)
        let glyphCount = Int(try reader.readUnsigned(2))
        try reader.skip(glyphCount * 8) // x,y position pairs (each 4 bytes Fixed 26.6 / DVI units)
        try reader.skip(glyphCount * 2) // glyph IDs
    }

    /// Opcode 253: parse and place native glyph array
    private func parseXDVGlyphArray(
        reader: inout DVIByteReader,
        state: inout DVIState,
        page: inout PageBuilder?,
        pointsPerDVIUnit: Double
    ) throws {
        let widthDVI = try reader.readSigned(4)
        let glyphCount = Int(try reader.readUnsigned(2))
        guard glyphCount > 0 else { return }

        var positions: [(x: Int64, y: Int64)] = []
        positions.reserveCapacity(glyphCount)
        for _ in 0..<glyphCount {
            let x = try reader.readSigned(4)
            let y = try reader.readSigned(4)
            positions.append((x: x, y: y))
        }

        var glyphIDs: [UInt16] = []
        glyphIDs.reserveCapacity(glyphCount)
        for _ in 0..<glyphCount {
            let gid = UInt16(try reader.readUnsigned(2))
            glyphIDs.append(gid)
        }

        guard let fontNumber = state.currentFontNumber else {
            warnings.append("XDV glyph array appeared before a font was selected.")
            state.h += widthDVI
            return
        }

        let fontDef = fonts[fontNumber]
        let fontSize = fontSizePoints(fontNumber: fontNumber, pointsPerDVIUnit: pointsPerDVIUnit)
        let color = fontDef?.nativeColor ?? state.currentColor

        var placedGlyphs: [DVINativeGlyphPosition] = []
        placedGlyphs.reserveCapacity(glyphCount)
        for i in 0..<glyphCount {
            let pos = positions[i]
            let gid = glyphIDs[i]
            let gx = Double(pos.x) * pointsPerDVIUnit
            let gy = Double(pos.y) * pointsPerDVIUnit
            placedGlyphs.append(DVINativeGlyphPosition(x: gx, y: gy, glyphID: gid))
        }

        if page != nil {
            let arrayItem = DVINativeGlyphArray(
                fontNumber: fontNumber,
                width: Double(widthDVI) * pointsPerDVIUnit,
                glyphs: placedGlyphs,
                x: xPoint(state.h, pointsPerDVIUnit),
                baselineY: yPoint(state.v, pointsPerDVIUnit),
                fontSize: fontSize,
                color: color
            )
            page?.add(.nativeGlyphArray(arrayItem))
        }

        state.h += widthDVI
    }

    /// Opcode 254: XDV_PIC_FILE — 1 byte flags + 24 bytes transform + 2 bytes page + 1 byte path length + path
    private func skipXDVPicFile(reader: inout DVIByteReader) throws {
        try reader.skip(1) // flags
        try reader.skip(24) // transform matrix (6 × 4 bytes Fixed)
        try reader.skip(2) // page number
        let pathLength = Int(try reader.readUnsigned(1))
        try reader.skip(pathLength) // file path
    }

    private func parseXDVPicFile(
        reader: inout DVIByteReader,
        state: inout DVIState,
        page: inout PageBuilder?,
        pointsPerDVIUnit: Double
    ) throws {
        let flags = try reader.readByte()
        var matrix: [Double] = []
        matrix.reserveCapacity(6)
        for _ in 0..<6 {
            let fixedVal = try reader.readSigned(4)
            matrix.append(Double(fixedVal) / 65536.0)
        }
        let pageNumber = Int(try reader.readUnsigned(2))
        let pathLength = Int(try reader.readUnsigned(1))
        let pathBytes = try reader.readBytes(pathLength)
        let filePath = String(data: pathBytes, encoding: .utf8)
            ?? String(data: pathBytes, encoding: .ascii)
            ?? ""

        if page != nil {
            let picItem = XDVPicItem(
                flags: flags,
                transform: matrix,
                pageNumber: pageNumber,
                path: filePath,
                x: xPoint(state.h, pointsPerDVIUnit),
                y: yPoint(state.v, pointsPerDVIUnit)
            )
            page?.add(.pic(picItem))
        }
    }

    /// Opcode 252 & 255: XDV_DEFINE_NATIVE_FONT — 4 bytes font number + 4 bytes size + 2 bytes flags +
    /// 1 byte psName length (l) + l bytes + 4 bytes rgba color + optional flag-dependent data
    private func readXDVDefineNativeFont(reader: inout DVIByteReader) throws -> DVIFontDefinition {
        let fontNumber = Int(try reader.readSigned(4))
        let scaledSize = Int64(try reader.readSigned(4)) // Fixed 16.16 point size in DVI units
        let flags = UInt16(try reader.readUnsigned(2))
        let psNameLength = Int(try reader.readUnsigned(1))
        let psNameBytes = try reader.readBytes(psNameLength)
        let fontName = String(data: psNameBytes, encoding: .utf8)
            ?? String(data: psNameBytes, encoding: .ascii)
            ?? ""
        _ = try reader.readUnsigned(4) // font index / order

        var nativeColor: DVIColor?
        let hasColored = (flags & 0x0200) != 0
        if hasColored {
            let rgba = try reader.readUnsigned(4)
            let r = Double((rgba >> 24) & 0xFF) / 255.0
            let g = Double((rgba >> 16) & 0xFF) / 255.0
            let b = Double((rgba >> 8) & 0xFF) / 255.0
            let a = Double(rgba & 0xFF) / 255.0
            nativeColor = DVIColor(red: r, green: g, blue: b, alpha: a)
        }

        let hasVariations = (flags & 0x0800) != 0
        if hasVariations {
            let variationCount = Int(try reader.readUnsigned(2))
            try reader.skip(variationCount * 8) // axis + value pairs
        }

        var nativeExtend: Double?
        let hasExtend = (flags & 0x1000) != 0
        if hasExtend {
            let rawExtend = try reader.readSigned(4)
            nativeExtend = Double(rawExtend) / 65536.0
        }

        var nativeSlant: Double?
        let hasSlant = (flags & 0x2000) != 0
        if hasSlant {
            let rawSlant = try reader.readSigned(4)
            nativeSlant = Double(rawSlant) / 65536.0
        }

        var nativeEmbolden: Double?
        let hasEmbolden = (flags & 0x4000) != 0
        if hasEmbolden {
            let rawEmbolden = try reader.readSigned(4)
            nativeEmbolden = Double(rawEmbolden) / 65536.0
        }

        return DVIFontDefinition(
            number: fontNumber,
            checksum: 0,
            scaledSize: scaledSize,
            designSize: scaledSize,
            area: "",
            name: fontName,
            isNative: true,
            nativeFlags: flags,
            nativeColor: nativeColor,
            nativeExtend: nativeExtend,
            nativeSlant: nativeSlant,
            nativeEmbolden: nativeEmbolden
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

    init(number: Int, counters: [Int64]) {
        self.number = number
        self.counters = counters
    }

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
                maxX = max(maxX, glyph.x + glyph.advance + glyph.italicCorrection + 72)
                maxY = max(maxY, glyph.baselineY + glyph.depth + 72)
            case .nativeGlyphArray(let array):
                maxX = max(maxX, array.x + array.width + 72)
                maxY = max(maxY, array.baselineY + array.fontSize + 72)
            case .pic(let pic):
                maxX = max(maxX, pic.x + 72)
                maxY = max(maxY, pic.y + 72)
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
