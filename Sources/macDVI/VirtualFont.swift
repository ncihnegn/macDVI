import Foundation

struct VFLocalFont {
    let localNumber: Int
    let checksum: UInt32
    let scaledSize: Int64
    let designSize: Int64
    let area: String
    let name: String
}

struct VFCharacterPacket {
    let characterCode: Int
    let widthFix: Int64
    let dviCommands: Data
}

final class VirtualFont {
    let designSize: Int64
    let checksum: UInt32
    let comment: String
    let localFonts: [VFLocalFont]
    let packets: [Int: VFCharacterPacket]

    init(data: Data) throws {
        var reader = DVIByteReader(data: data)
        let pre = try reader.readByte()
        guard pre == 247 else {
            throw DVIError.malformed("VF: missing preamble opcode")
        }
        let id = try reader.readByte()
        guard id == 202 else {
            throw DVIError.malformed("VF: unexpected id \(id)")
        }
        let commentLength = Int(try reader.readUnsigned(1))
        let commentBytes = try reader.readBytes(commentLength)
        comment = String(data: commentBytes, encoding: .utf8)
            ?? String(data: commentBytes, encoding: .ascii)
            ?? ""
        checksum = UInt32(try reader.readUnsigned(4))
        designSize = Int64(try reader.readUnsigned(4))

        var locals: [VFLocalFont] = []
        var collected: [Int: VFCharacterPacket] = [:]

        while !reader.isAtEnd {
            let opcode = try reader.readByte()
            if opcode == 248 {
                break
            }
            switch opcode {
            case 0...241:
                let length = Int(opcode)
                let cc = Int(try reader.readUnsigned(1))
                let widthFix = Int64(try reader.readUnsigned(3))
                let commands = try reader.readBytes(length)
                collected[cc] = VFCharacterPacket(
                    characterCode: cc,
                    widthFix: widthFix,
                    dviCommands: commands
                )
            case 242:
                let length = Int(try reader.readUnsigned(4))
                let cc = Int(try reader.readUnsigned(4))
                let widthFix = try reader.readSigned(4)
                let commands = try reader.readBytes(length)
                collected[cc] = VFCharacterPacket(
                    characterCode: cc,
                    widthFix: widthFix,
                    dviCommands: commands
                )
            case 243...246:
                let local = try VirtualFont.readLocalFont(opcode: opcode, reader: &reader)
                locals.append(local)
            default:
                throw DVIError.malformed("VF: unsupported opcode \(opcode)")
            }
        }

        localFonts = locals
        packets = collected
    }

    private static func readLocalFont(opcode: UInt8, reader: inout DVIByteReader) throws -> VFLocalFont {
        let number = Int(try reader.readUnsigned(Int(opcode - 242)))
        let checksum = UInt32(try reader.readUnsigned(4))
        let scaled = Int64(try reader.readUnsigned(4))
        let design = Int64(try reader.readUnsigned(4))
        let areaLength = Int(try reader.readUnsigned(1))
        let nameLength = Int(try reader.readUnsigned(1))
        let areaBytes = try reader.readBytes(areaLength)
        let nameBytes = try reader.readBytes(nameLength)
        return VFLocalFont(
            localNumber: number,
            checksum: checksum,
            scaledSize: scaled,
            designSize: design,
            area: String(data: areaBytes, encoding: .utf8) ?? String(data: areaBytes, encoding: .ascii) ?? "",
            name: String(data: nameBytes, encoding: .utf8) ?? String(data: nameBytes, encoding: .ascii) ?? ""
        )
    }
}

final class VirtualFontProvider {
    private var cache: [String: VirtualFont] = [:]
    private var missing: Set<String> = []
    private let searchDirectories: [URL]

    init(documentURL: URL) {
        searchDirectories = [
            documentURL.deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]
    }

    func virtualFont(for definition: DVIFontDefinition) -> VirtualFont? {
        let key = definition.texName.lowercased()
        if let cached = cache[key] {
            return cached
        }
        if missing.contains(key) {
            return nil
        }
        guard let url = locateVF(definition),
              let data = try? Data(contentsOf: url),
              let virtualFont = try? VirtualFont(data: data) else {
            missing.insert(key)
            return nil
        }
        cache[key] = virtualFont
        return virtualFont
    }

    private func locateVF(_ definition: DVIFontDefinition) -> URL? {
        let baseNames = definition.area.isEmpty
            ? [definition.name]
            : [definition.area + definition.name, definition.name]
        let fileNames = baseNames.map { "\($0).vf" }

        for directory in searchDirectories {
            for fileName in fileNames {
                let url = directory.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        if !definition.area.isEmpty {
            let areaURL = URL(fileURLWithPath: definition.area, isDirectory: true)
            if areaURL.path.hasPrefix("/") {
                for fileName in fileNames {
                    let url = areaURL.appendingPathComponent(fileName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                }
            }
        }

        for fileName in fileNames {
            if let path = TeXFileLocator.findFile(named: fileName) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
