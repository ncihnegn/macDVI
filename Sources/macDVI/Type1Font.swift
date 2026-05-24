import CoreGraphics
import CoreText
import Foundation

final class Type1Font {
    let postScriptName: String
    let unitsPerEm: Double

    private let cgFont: CGFont
    private let ctFont: CTFont
    private var pathCache: [String: CGPath] = [:]
    private var missingGlyphs: Set<String> = []

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw DVIError.malformed("could not create data provider for Type 1 font at \(url.path)")
        }
        guard let cg = CGFont(provider) else {
            throw DVIError.malformed("could not load Type 1 font at \(url.path)")
        }

        cgFont = cg
        unitsPerEm = cg.unitsPerEm > 0 ? Double(cg.unitsPerEm) : 1000
        postScriptName = (cg.postScriptName as String?) ?? url.deletingPathExtension().lastPathComponent

        let matrix = CGAffineTransform.identity
        ctFont = CTFontCreateWithGraphicsFont(cg, CGFloat(unitsPerEm), nil, nil)
        _ = matrix
    }

    func path(forGlyphNamed name: String) -> CGPath? {
        if let cached = pathCache[name] {
            return cached
        }
        if missingGlyphs.contains(name) {
            return nil
        }
        let glyph = cgFont.getGlyphWithGlyphName(name: name as CFString)
        guard glyph != 0 || name == ".notdef" else {
            missingGlyphs.insert(name)
            return nil
        }
        guard let path = CTFontCreatePathForGlyph(ctFont, glyph, nil) else {
            missingGlyphs.insert(name)
            return nil
        }
        pathCache[name] = path
        return path
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
