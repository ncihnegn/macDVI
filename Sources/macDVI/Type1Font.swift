import CoreGraphics
import CoreText
import Foundation

enum OutlineFontKind {
    case type1
    case openType
}

final class OutlineFont {
    let kind: OutlineFontKind
    let postScriptName: String
    let unitsPerEm: Double

    private let cgFont: CGFont
    private let ctFont: CTFont
    private var pathCache: [PathCacheKey: CGPath] = [:]
    private var missingGlyphs: Set<PathCacheKey> = []

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw DVIError.malformed("could not create data provider for font at \(url.path)")
        }
        guard let cg = CGFont(provider) else {
            throw DVIError.malformed("could not load font at \(url.path)")
        }

        cgFont = cg
        unitsPerEm = cg.unitsPerEm > 0 ? Double(cg.unitsPerEm) : 1000
        postScriptName = (cg.postScriptName as String?) ?? url.deletingPathExtension().lastPathComponent
        ctFont = CTFontCreateWithGraphicsFont(cg, CGFloat(unitsPerEm), nil, nil)

        let ext = url.pathExtension.lowercased()
        kind = (ext == "pfb" || ext == "pfa") ? .type1 : .openType
    }

    func path(forGlyphNamed name: String) -> CGPath? {
        let key = PathCacheKey.name(name)
        if let cached = pathCache[key] { return cached }
        if missingGlyphs.contains(key) { return nil }

        let glyph = cgFont.getGlyphWithGlyphName(name: name as CFString)
        guard glyph != 0 || name == ".notdef" else {
            missingGlyphs.insert(key)
            return nil
        }
        guard let path = CTFontCreatePathForGlyph(ctFont, glyph, nil) else {
            missingGlyphs.insert(key)
            return nil
        }
        pathCache[key] = path
        return path
    }

    func path(forUnicode scalar: UInt32) -> CGPath? {
        let key = PathCacheKey.unicode(scalar)
        if let cached = pathCache[key] { return cached }
        if missingGlyphs.contains(key) { return nil }

        guard let unicode = UnicodeScalar(scalar) else {
            missingGlyphs.insert(key)
            return nil
        }
        let utf16 = Array(String(unicode).utf16)
        var glyphs = Array<CGGlyph>(repeating: 0, count: utf16.count)
        let mapped = utf16.withUnsafeBufferPointer { buf in
            CTFontGetGlyphsForCharacters(ctFont, buf.baseAddress!, &glyphs, utf16.count)
        }
        guard mapped, let glyph = glyphs.first, glyph != 0 else {
            missingGlyphs.insert(key)
            return nil
        }
        guard let path = CTFontCreatePathForGlyph(ctFont, glyph, nil) else {
            missingGlyphs.insert(key)
            return nil
        }
        pathCache[key] = path
        return path
    }

    private enum PathCacheKey: Hashable {
        case name(String)
        case unicode(UInt32)
    }
}

final class OutlineFontProvider {
    private var cache: [String: OutlineFont] = [:]
    private var missingFonts: Set<String> = []
    private var mapEntries: [String: FontMapEntry]?
    private let searchDirectories: [URL]

    init(documentURL: URL) {
        searchDirectories = [
            documentURL.deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
    }

    func font(for definition: DVIFontDefinition) -> OutlineFont? {
        let key = definition.texName.lowercased()
        if let cached = cache[key] {
            return cached
        }
        if missingFonts.contains(key) {
            return nil
        }

        guard let url = fontURL(for: definition),
              let font = try? OutlineFont(url: url) else {
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
            ["\(name).otf", "\(name).ttf", "\(name).pfb", "\(name).pfa"]
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

    private func mapEntry(for fontName: String) -> FontMapEntry? {
        if mapEntries == nil {
            mapEntries = FontMapLoader.loadEntries()
        }
        return mapEntries?[fontName.lowercased()]
    }
}

private struct FontMapEntry {
    let postScriptName: String
    let fileName: String
}

private enum FontMapLoader {
    static func loadEntries() -> [String: FontMapEntry] {
        var entries: [String: FontMapEntry] = [:]
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

    private static func parseLine(_ line: String) -> (key: String, value: FontMapEntry)? {
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
            return lowercased.contains(".pfb")
                || lowercased.contains(".pfa")
                || lowercased.contains(".otf")
                || lowercased.contains(".ttf")
        }) else {
            return nil
        }

        let fileName = fileToken
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>[]"))
        return (
            key: tokens[0].lowercased(),
            value: FontMapEntry(postScriptName: tokens[1], fileName: fileName)
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

typealias Type1Font = OutlineFont
typealias Type1FontProvider = OutlineFontProvider
