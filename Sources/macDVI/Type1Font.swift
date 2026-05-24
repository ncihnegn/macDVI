import CoreGraphics
import Foundation

final class Type1Font {
    let postScriptName: String
    let unitsPerEm: Double

    private let charStrings: [String: [UInt8]]
    private let subrs: [[UInt8]]
    private var pathCache: [String: CGPath] = [:]
    private var missingGlyphs: Set<String> = []

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let parts = try Type1ProgramParts(data: data)
        let clearText = String(data: parts.clearText, encoding: .ascii) ?? ""
        let decryptedPrivate = Type1Encryption.decrypt(parts.encryptedPrivate, key: 55665, discardPrefixCount: 4)

        postScriptName = Type1Parser.postScriptName(from: clearText) ?? url.deletingPathExtension().lastPathComponent
        unitsPerEm = Type1Parser.unitsPerEm(from: clearText) ?? 1000

        let privatePrefix = Type1Parser.privatePrefix(from: decryptedPrivate)
        let lenIV = Type1Parser.integer(named: "lenIV", in: privatePrefix) ?? 4
        subrs = Type1Parser.subrs(from: decryptedPrivate, lenIV: lenIV)
        charStrings = Type1Parser.charStrings(from: decryptedPrivate, lenIV: lenIV)
    }

    func path(forGlyphNamed name: String) -> CGPath? {
        if let cached = pathCache[name] {
            return cached
        }
        if missingGlyphs.contains(name) {
            return nil
        }
        guard let bytes = charStrings[name] else {
            missingGlyphs.insert(name)
            return nil
        }

        let interpreter = Type1CharStringInterpreter(font: self)
        guard let path = interpreter.path(from: bytes, depth: 0) else {
            missingGlyphs.insert(name)
            return nil
        }
        pathCache[name] = path
        return path
    }

    fileprivate func subr(at index: Int) -> [UInt8]? {
        guard index >= 0, index < subrs.count else {
            return nil
        }
        return subrs[index]
    }
}

final class Type1FontProvider {
    private var cache: [String: Type1Font] = [:]
    private var missingFonts: Set<String> = []
    private var mapEntries: [String: Type1MapEntry]?
    private let searchDirectories: [URL]

    init(documentURL: URL) {
        searchDirectories = [
            documentURL.deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
    }

    func font(for definition: DVIFontDefinition) -> Type1Font? {
        let key = definition.texName.lowercased()
        if let cached = cache[key] {
            return cached
        }
        if missingFonts.contains(key) {
            return nil
        }

        guard let url = fontURL(for: definition),
              let font = try? Type1Font(url: url) else {
            missingFonts.insert(key)
            return nil
        }
        cache[key] = font
        return font
    }

    private func fontURL(for definition: DVIFontDefinition) -> URL? {
        for url in localCandidateURLs(for: definition) where FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        if let mapEntry = mapEntry(for: definition.name),
           let url = locatedURL(fileName: mapEntry.fileName) {
            return url
        }

        for fileName in directFileNames(for: definition) {
            if let url = locatedURL(fileName: fileName) {
                return url
            }
        }
        return nil
    }

    private func localCandidateURLs(for definition: DVIFontDefinition) -> [URL] {
        var urls: [URL] = []
        let fileNames = directFileNames(for: definition)

        if !definition.area.isEmpty {
            let areaURL = URL(fileURLWithPath: definition.area, isDirectory: true)
            if areaURL.path.hasPrefix("/") {
                for fileName in fileNames {
                    urls.append(areaURL.appendingPathComponent(fileName))
                }
            }

            for directory in searchDirectories {
                for fileName in fileNames {
                    urls.append(directory.appendingPathComponent(definition.area).appendingPathComponent(fileName))
                }
            }
        }

        for directory in searchDirectories {
            for fileName in fileNames {
                urls.append(directory.appendingPathComponent(fileName))
            }
        }
        return urls
    }

    private func directFileNames(for definition: DVIFontDefinition) -> [String] {
        let names = definition.area.isEmpty
            ? [definition.name]
            : [definition.area + definition.name, definition.name]
        return names.flatMap { name in
            ["\(name).pfb", "\(name).pfa"]
        }
    }

    private func locatedURL(fileName: String) -> URL? {
        if fileName.hasPrefix("/"), FileManager.default.fileExists(atPath: fileName) {
            return URL(fileURLWithPath: fileName)
        }
        if let path = TeXFileLocator.findFile(named: fileName) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func mapEntry(for fontName: String) -> Type1MapEntry? {
        if mapEntries == nil {
            mapEntries = Type1MapLoader.loadEntries()
        }
        return mapEntries?[fontName.lowercased()]
    }
}

private struct Type1MapEntry {
    let postScriptName: String
    let fileName: String
}

private enum Type1MapLoader {
    static func loadEntries() -> [String: Type1MapEntry] {
        var entries: [String: Type1MapEntry] = [:]
        for mapName in ["pdftex.map", "psfonts.map"] {
            guard let path = TeXFileLocator.findFile(named: mapName),
                  let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }
            for line in text.components(separatedBy: .newlines) {
                guard let entry = parseLine(line) else { continue }
                entries[entry.key] = entry.value
            }
        }
        return entries
    }

    private static func parseLine(_ line: String) -> (key: String, value: Type1MapEntry)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("%"), !trimmed.hasPrefix("#") else {
            return nil
        }

        let tokens = tokenize(trimmed)
        guard tokens.count >= 2 else {
            return nil
        }
        guard let fileToken = tokens.first(where: { token in
            let lowercased = token.lowercased()
            return lowercased.contains(".pfb") || lowercased.contains(".pfa")
        }) else {
            return nil
        }

        let fileName = fileToken
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>[]"))
        return (
            key: tokens[0].lowercased(),
            value: Type1MapEntry(postScriptName: tokens[1], fileName: fileName)
        )
    }

    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false

        for character in line {
            if character == "\"" {
                inQuote.toggle()
                continue
            }
            if character.isWhitespace, !inQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

private struct Type1ProgramParts {
    let clearText: Data
    let encryptedPrivate: [UInt8]

    init(data: Data) throws {
        if data.first == 0x80 {
            var offset = 0
            var clear = Data()
            var encrypted: [UInt8] = []

            while offset < data.count {
                guard offset + 2 <= data.count, data[offset] == 0x80 else {
                    throw DVIError.malformed("invalid Type 1 PFB segment")
                }
                let kind = data[offset + 1]
                offset += 2
                if kind == 0x03 {
                    break
                }
                guard offset + 4 <= data.count else {
                    throw DVIError.malformed("invalid Type 1 PFB segment")
                }

                let length = Int(data[offset])
                    | (Int(data[offset + 1]) << 8)
                    | (Int(data[offset + 2]) << 16)
                    | (Int(data[offset + 3]) << 24)
                offset += 4
                guard length >= 0, offset + length <= data.count else {
                    throw DVIError.malformed("invalid Type 1 PFB segment length")
                }

                let segment = data[offset..<(offset + length)]
                if kind == 0x01 {
                    clear.append(segment)
                } else if kind == 0x02 {
                    encrypted.append(contentsOf: segment)
                }
                offset += length
            }

            guard !encrypted.isEmpty else {
                throw DVIError.malformed("Type 1 font does not contain an encrypted private dictionary")
            }
            self.clearText = clear
            self.encryptedPrivate = encrypted
            return
        }

        let marker = Data("eexec".utf8)
        guard let range = data.range(of: marker) else {
            throw DVIError.malformed("Type 1 PFA font does not contain eexec data")
        }

        clearText = data.subdata(in: data.startIndex..<range.upperBound)
        encryptedPrivate = Type1ProgramParts.hexBytes(from: data.subdata(in: range.upperBound..<data.endIndex))
    }

    private static func hexBytes(from data: Data) -> [UInt8] {
        var nibbles: [UInt8] = []
        nibbles.reserveCapacity(data.count)
        for byte in data {
            switch byte {
            case 48...57:
                nibbles.append(byte - 48)
            case 65...70:
                nibbles.append(byte - 55)
            case 97...102:
                nibbles.append(byte - 87)
            default:
                continue
            }
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(nibbles.count / 2)
        var index = 0
        while index + 1 < nibbles.count {
            bytes.append((nibbles[index] << 4) | nibbles[index + 1])
            index += 2
        }
        return bytes
    }
}

private enum Type1Parser {
    static func postScriptName(from text: String) -> String? {
        guard let range = text.range(of: "/FontName") else {
            return nil
        }
        let suffix = text[range.upperBound...]
        for token in suffix.split(whereSeparator: { $0.isWhitespace }) {
            if token.hasPrefix("/") {
                return String(token.dropFirst())
            }
            if token != "def" {
                return String(token)
            }
        }
        return nil
    }

    static func unitsPerEm(from text: String) -> Double? {
        guard let range = text.range(of: "/FontMatrix"),
              let open = text[range.upperBound...].firstIndex(of: "["),
              let close = text[open...].firstIndex(of: "]") else {
            return nil
        }

        let matrixValues = text[text.index(after: open)..<close]
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .compactMap { Double($0) }
        guard let scale = matrixValues.first, scale != 0 else {
            return nil
        }
        return 1.0 / abs(scale)
    }

    static func privatePrefix(from data: [UInt8]) -> Data {
        let privateData = Data(data)
        if let charStringsRange = privateData.range(of: Data("/CharStrings".utf8)) {
            return privateData.subdata(in: privateData.startIndex..<charStringsRange.lowerBound)
        }
        return privateData
    }

    static func integer(named name: String, in data: Data) -> Int? {
        var scanner = Type1TokenScanner(data: data)
        while let token = scanner.nextToken() {
            guard token == "/\(name)" else { continue }
            if let value = scanner.nextToken().flatMap(Int.init) {
                return value
            }
        }
        return nil
    }

    static func subrs(from data: [UInt8], lenIV: Int) -> [[UInt8]] {
        let privateData = Data(data)
        guard let subrsRange = privateData.range(of: Data("/Subrs".utf8)) else {
            return []
        }
        let end = privateData.range(of: Data("/CharStrings".utf8))?.lowerBound ?? privateData.endIndex
        let subrsData = privateData.subdata(in: subrsRange.lowerBound..<end)
        var scanner = Type1TokenScanner(data: subrsData)
        var subrs: [[UInt8]] = []

        while let token = scanner.nextToken() {
            guard token == "dup",
                  let indexToken = scanner.nextToken(),
                  let index = Int(indexToken),
                  let lengthToken = scanner.nextToken(),
                  let length = Int(lengthToken),
                  let operatorToken = scanner.nextToken(),
                  isBinaryReadOperator(operatorToken),
                  let encrypted = scanner.readBinary(length: length) else {
                continue
            }

            if index >= subrs.count {
                subrs.append(contentsOf: Array(repeating: [], count: index - subrs.count + 1))
            }
            subrs[index] = Type1Encryption.decrypt(encrypted, key: 4330, discardPrefixCount: max(lenIV, 0))
        }
        return subrs
    }

    static func charStrings(from data: [UInt8], lenIV: Int) -> [String: [UInt8]] {
        let privateData = Data(data)
        guard let range = privateData.range(of: Data("/CharStrings".utf8)) else {
            return [:]
        }
        let charStringsData = privateData.subdata(in: range.lowerBound..<privateData.endIndex)
        var scanner = Type1TokenScanner(data: charStringsData)
        var charStrings: [String: [UInt8]] = [:]

        while let token = scanner.nextToken() {
            guard token.hasPrefix("/"), token.count > 1 else {
                continue
            }
            let glyphName = String(token.dropFirst())
            let restoreOffset = scanner.offset
            guard let lengthToken = scanner.nextToken(),
                  let length = Int(lengthToken),
                  let operatorToken = scanner.nextToken(),
                  isBinaryReadOperator(operatorToken),
                  let encrypted = scanner.readBinary(length: length) else {
                scanner.offset = restoreOffset
                continue
            }
            charStrings[glyphName] = Type1Encryption.decrypt(encrypted, key: 4330, discardPrefixCount: max(lenIV, 0))
        }
        return charStrings
    }

    private static func isBinaryReadOperator(_ token: String) -> Bool {
        token == "RD" || token == "-|"
    }
}

private struct Type1TokenScanner {
    let data: Data
    var offset: Int = 0

    mutating func nextToken() -> String? {
        skipWhitespaceAndComments()
        guard offset < data.count else {
            return nil
        }

        let start = offset
        let first = data[offset]
        if isDelimiter(first), first != 47 {
            offset += 1
            return String(bytes: data[start..<offset], encoding: .ascii)
        }

        offset += 1
        while offset < data.count {
            let byte = data[offset]
            if isWhitespace(byte) || isDelimiter(byte) {
                break
            }
            offset += 1
        }
        return String(bytes: data[start..<offset], encoding: .ascii)
    }

    mutating func readBinary(length: Int) -> [UInt8]? {
        guard length >= 0 else {
            return nil
        }
        if offset < data.count, isWhitespace(data[offset]) {
            offset += 1
        }
        guard offset + length <= data.count else {
            return nil
        }

        let bytes = Array(data[offset..<(offset + length)])
        offset += length
        return bytes
    }

    private mutating func skipWhitespaceAndComments() {
        while offset < data.count {
            let byte = data[offset]
            if isWhitespace(byte) {
                offset += 1
                continue
            }
            if byte == 37 {
                while offset < data.count, data[offset] != 10, data[offset] != 13 {
                    offset += 1
                }
                continue
            }
            break
        }
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32
    }

    private func isDelimiter(_ byte: UInt8) -> Bool {
        switch byte {
        case 40, 41, 60, 62, 91, 93, 123, 125:
            return true
        default:
            return false
        }
    }
}

private enum Type1Encryption {
    static func decrypt(_ bytes: [UInt8], key: UInt16, discardPrefixCount: Int) -> [UInt8] {
        var state = UInt32(key)
        var plainBytes: [UInt8] = []
        plainBytes.reserveCapacity(bytes.count)

        for cipher in bytes {
            let plain = cipher ^ UInt8((state >> 8) & 0xff)
            plainBytes.append(plain)
            state = ((UInt32(cipher) + state) * 52845 + 22719) & 0xffff
        }

        guard discardPrefixCount > 0, discardPrefixCount < plainBytes.count else {
            return discardPrefixCount >= plainBytes.count ? [] : plainBytes
        }
        return Array(plainBytes.dropFirst(discardPrefixCount))
    }
}

private final class Type1CharStringInterpreter {
    private let font: Type1Font
    private let path = CGMutablePath()
    private var stack: [Double] = []
    private var currentX = 0.0
    private var currentY = 0.0
    private var hasCurrentPoint = false
    private var otherSubrResults: [Double] = []

    init(font: Type1Font) {
        self.font = font
    }

    func path(from bytes: [UInt8], depth: Int) -> CGPath? {
        _ = execute(bytes, depth: depth)
        return path.copy()
    }

    private func execute(_ bytes: [UInt8], depth: Int) -> Bool {
        guard depth < 16 else {
            return false
        }

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1

            if byte >= 32 {
                guard let number = readNumber(firstByte: byte, bytes: bytes, index: &index) else {
                    return false
                }
                stack.append(number)
                continue
            }

            if byte == 12 {
                guard index < bytes.count else {
                    return false
                }
                let escaped = bytes[index]
                index += 1
                if executeEscapedCommand(escaped, depth: depth) {
                    return true
                }
            } else if executeCommand(byte, depth: depth) {
                return true
            }
        }
        return false
    }

    private func executeCommand(_ command: UInt8, depth: Int) -> Bool {
        switch command {
        case 1, 3:
            stack.removeAll(keepingCapacity: true)
        case 4:
            let dy = pop()
            moveBy(dx: 0, dy: dy)
            stack.removeAll(keepingCapacity: true)
        case 5:
            while stack.count >= 2 {
                lineBy(dx: stack.removeFirst(), dy: stack.removeFirst())
            }
            stack.removeAll(keepingCapacity: true)
        case 6:
            var horizontal = true
            while !stack.isEmpty {
                let value = stack.removeFirst()
                lineBy(dx: horizontal ? value : 0, dy: horizontal ? 0 : value)
                horizontal.toggle()
            }
        case 7:
            var vertical = true
            while !stack.isEmpty {
                let value = stack.removeFirst()
                lineBy(dx: vertical ? 0 : value, dy: vertical ? value : 0)
                vertical.toggle()
            }
        case 8:
            while stack.count >= 6 {
                curveBy(
                    dx1: stack.removeFirst(),
                    dy1: stack.removeFirst(),
                    dx2: stack.removeFirst(),
                    dy2: stack.removeFirst(),
                    dx3: stack.removeFirst(),
                    dy3: stack.removeFirst()
                )
            }
            stack.removeAll(keepingCapacity: true)
        case 9:
            path.closeSubpath()
            stack.removeAll(keepingCapacity: true)
        case 10:
            let subrIndex = Int(pop().rounded())
            if let subr = font.subr(at: subrIndex) {
                _ = execute(subr, depth: depth + 1)
            }
        case 11:
            return true
        case 13:
            let sideBearingX = stack.count >= 2 ? stack[stack.count - 2] : 0
            currentX = sideBearingX
            currentY = 0
            hasCurrentPoint = false
            stack.removeAll(keepingCapacity: true)
        case 14:
            stack.removeAll(keepingCapacity: true)
            return true
        case 21:
            let dy = pop()
            let dx = pop()
            moveBy(dx: dx, dy: dy)
            stack.removeAll(keepingCapacity: true)
        case 22:
            let dx = pop()
            moveBy(dx: dx, dy: 0)
            stack.removeAll(keepingCapacity: true)
        case 30:
            while stack.count >= 4 {
                let dy1 = stack.removeFirst()
                let dx2 = stack.removeFirst()
                let dy2 = stack.removeFirst()
                let dx3 = stack.removeFirst()
                let c1 = point(x: currentX, y: currentY + dy1)
                let c2 = point(x: currentX + dx2, y: currentY + dy1 + dy2)
                let end = point(x: currentX + dx2 + dx3, y: currentY + dy1 + dy2)
                curve(to: end, control1: c1, control2: c2)
            }
            stack.removeAll(keepingCapacity: true)
        case 31:
            while stack.count >= 4 {
                let dx1 = stack.removeFirst()
                let dx2 = stack.removeFirst()
                let dy2 = stack.removeFirst()
                let dy3 = stack.removeFirst()
                let c1 = point(x: currentX + dx1, y: currentY)
                let c2 = point(x: currentX + dx1 + dx2, y: currentY + dy2)
                let end = point(x: currentX + dx1 + dx2, y: currentY + dy2 + dy3)
                curve(to: end, control1: c1, control2: c2)
            }
            stack.removeAll(keepingCapacity: true)
        default:
            stack.removeAll(keepingCapacity: true)
        }
        return false
    }

    private func executeEscapedCommand(_ command: UInt8, depth: Int) -> Bool {
        switch command {
        case 0, 1, 2:
            stack.removeAll(keepingCapacity: true)
        case 6:
            guard stack.count >= 5 else {
                stack.removeAll(keepingCapacity: true)
                return false
            }
            let achar = Int(pop().rounded())
            let bchar = Int(pop().rounded())
            let ady = pop()
            let adx = pop()
            _ = pop()
            appendStandardGlyph(code: bchar, dx: 0, dy: 0)
            appendStandardGlyph(code: achar, dx: adx, dy: ady)
            stack.removeAll(keepingCapacity: true)
            return true
        case 7:
            let sideBearingY = stack.count >= 4 ? stack[stack.count - 4 + 1] : 0
            let sideBearingX = stack.count >= 4 ? stack[stack.count - 4] : 0
            currentX = sideBearingX
            currentY = sideBearingY
            hasCurrentPoint = false
            stack.removeAll(keepingCapacity: true)
        case 12:
            let divisor = pop()
            let dividend = pop()
            stack.append(divisor == 0 ? 0 : dividend / divisor)
        case 16:
            let otherSubr = Int(pop().rounded())
            let argumentCount = Int(pop().rounded())
            let arguments = popMany(argumentCount)
            if otherSubr == 0 {
                otherSubrResults = [currentX, currentY]
            } else if otherSubr == 3, arguments.count >= 2 {
                currentX = arguments[arguments.count - 2]
                currentY = arguments[arguments.count - 1]
                otherSubrResults = [currentX, currentY]
            } else {
                otherSubrResults.removeAll(keepingCapacity: true)
            }
        case 17:
            stack.append(otherSubrResults.popLast() ?? 0)
        case 33:
            let y = pop()
            let x = pop()
            currentX = x
            currentY = y
            ensureCurrentPoint()
            stack.removeAll(keepingCapacity: true)
        default:
            stack.removeAll(keepingCapacity: true)
        }
        return false
    }

    private func readNumber(firstByte byte: UInt8, bytes: [UInt8], index: inout Int) -> Double? {
        switch byte {
        case 32...246:
            return Double(Int(byte) - 139)
        case 247...250:
            guard index < bytes.count else { return nil }
            let next = Int(bytes[index])
            index += 1
            return Double((Int(byte) - 247) * 256 + next + 108)
        case 251...254:
            guard index < bytes.count else { return nil }
            let next = Int(bytes[index])
            index += 1
            return Double(-((Int(byte) - 251) * 256) - next - 108)
        case 255:
            guard index + 4 <= bytes.count else { return nil }
            let value = UInt32(bytes[index]) << 24
                | UInt32(bytes[index + 1]) << 16
                | UInt32(bytes[index + 2]) << 8
                | UInt32(bytes[index + 3])
            index += 4
            return Double(Int32(bitPattern: value))
        default:
            return nil
        }
    }

    private func moveBy(dx: Double, dy: Double) {
        currentX += dx
        currentY += dy
        path.move(to: point(x: currentX, y: currentY))
        hasCurrentPoint = true
    }

    private func lineBy(dx: Double, dy: Double) {
        ensureCurrentPoint()
        currentX += dx
        currentY += dy
        path.addLine(to: point(x: currentX, y: currentY))
    }

    private func curveBy(dx1: Double, dy1: Double, dx2: Double, dy2: Double, dx3: Double, dy3: Double) {
        ensureCurrentPoint()
        let control1 = point(x: currentX + dx1, y: currentY + dy1)
        let control2 = point(x: Double(control1.x) + dx2, y: Double(control1.y) + dy2)
        let end = point(x: Double(control2.x) + dx3, y: Double(control2.y) + dy3)
        curve(to: end, control1: control1, control2: control2)
    }

    private func curve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        ensureCurrentPoint()
        path.addCurve(to: end, control1: control1, control2: control2)
        currentX = Double(end.x)
        currentY = Double(end.y)
    }

    private func ensureCurrentPoint() {
        if !hasCurrentPoint {
            path.move(to: point(x: currentX, y: currentY))
            hasCurrentPoint = true
        }
    }

    private func appendStandardGlyph(code: Int, dx: Double, dy: Double) {
        guard let glyphName = Type1StandardEncoding.glyphName(for: code),
              let glyphPath = font.path(forGlyphNamed: glyphName) else {
            return
        }
        let transform = CGAffineTransform(translationX: CGFloat(dx), y: CGFloat(dy))
        path.addPath(glyphPath, transform: transform)
    }

    private func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    private func pop() -> Double {
        stack.popLast() ?? 0
    }

    private func popMany(_ count: Int) -> [Double] {
        guard count > 0 else {
            return []
        }
        let start = max(0, stack.count - count)
        let values = Array(stack[start..<stack.count])
        stack.removeSubrange(start..<stack.count)
        return values
    }
}

private enum Type1StandardEncoding {
    static func glyphName(for code: Int) -> String? {
        guard code >= 0, code < names.count else {
            return nil
        }
        return names[code]
    }

    private static let names: [String?] = {
        var names = Array<String?>(repeating: nil, count: 256)
        let entries: [Int: String] = [
            32: "space", 33: "exclam", 34: "quotedbl", 35: "numbersign", 36: "dollar",
            37: "percent", 38: "ampersand", 39: "quoteright", 40: "parenleft",
            41: "parenright", 42: "asterisk", 43: "plus", 44: "comma", 45: "hyphen",
            46: "period", 47: "slash", 48: "zero", 49: "one", 50: "two", 51: "three",
            52: "four", 53: "five", 54: "six", 55: "seven", 56: "eight", 57: "nine",
            58: "colon", 59: "semicolon", 60: "less", 61: "equal", 62: "greater",
            63: "question", 64: "at", 65: "A", 66: "B", 67: "C", 68: "D", 69: "E",
            70: "F", 71: "G", 72: "H", 73: "I", 74: "J", 75: "K", 76: "L",
            77: "M", 78: "N", 79: "O", 80: "P", 81: "Q", 82: "R", 83: "S",
            84: "T", 85: "U", 86: "V", 87: "W", 88: "X", 89: "Y", 90: "Z",
            91: "bracketleft", 92: "backslash", 93: "bracketright", 94: "asciicircum",
            95: "underscore", 96: "quoteleft", 97: "a", 98: "b", 99: "c", 100: "d",
            101: "e", 102: "f", 103: "g", 104: "h", 105: "i", 106: "j", 107: "k",
            108: "l", 109: "m", 110: "n", 111: "o", 112: "p", 113: "q", 114: "r",
            115: "s", 116: "t", 117: "u", 118: "v", 119: "w", 120: "x", 121: "y",
            122: "z", 123: "braceleft", 124: "bar", 125: "braceright", 126: "asciitilde",
            161: "exclamdown", 162: "cent", 163: "sterling", 164: "fraction",
            165: "yen", 166: "florin", 167: "section", 168: "currency",
            169: "quotesingle", 170: "quotedblleft", 171: "guillemotleft",
            172: "guilsinglleft", 173: "guilsinglright", 174: "fi", 175: "fl",
            177: "endash", 178: "dagger", 179: "daggerdbl", 180: "periodcentered",
            182: "paragraph", 183: "bullet", 184: "quotesinglbase",
            185: "quotedblbase", 186: "quotedblright", 187: "guillemotright",
            188: "ellipsis", 189: "perthousand", 191: "questiondown",
            193: "grave", 194: "acute", 195: "circumflex", 196: "tilde",
            197: "macron", 198: "breve", 199: "dotaccent", 200: "dieresis",
            202: "ring", 203: "cedilla", 205: "hungarumlaut", 206: "ogonek",
            207: "caron", 208: "emdash", 225: "AE", 227: "ordfeminine",
            232: "Lslash", 233: "Oslash", 234: "OE", 235: "ordmasculine",
            241: "ae", 245: "dotlessi", 248: "lslash", 249: "oslash",
            250: "oe", 251: "germandbls"
        ]
        for (code, name) in entries {
            names[code] = name
        }
        return names
    }()
}
