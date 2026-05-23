import Foundation

struct DVIByteReader {
    let data: Data
    private(set) var offset: Int = 0

    var isAtEnd: Bool {
        offset >= data.count
    }

    var remainingCount: Int {
        max(0, data.count - offset)
    }

    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else {
            throw DVIError.malformed("unexpected end of file")
        }
        let byte = data[offset]
        offset += 1
        return byte
    }

    mutating func readUnsigned(_ byteCount: Int) throws -> UInt64 {
        guard byteCount >= 0 && byteCount <= 8 else {
            throw DVIError.malformed("invalid unsigned integer width \(byteCount)")
        }
        guard offset + byteCount <= data.count else {
            throw DVIError.malformed("unexpected end of file while reading integer")
        }
        var value: UInt64 = 0
        for _ in 0..<byteCount {
            value = (value << 8) | UInt64(data[offset])
            offset += 1
        }
        return value
    }

    mutating func readSigned(_ byteCount: Int) throws -> Int64 {
        let unsigned = try readUnsigned(byteCount)
        guard byteCount > 0 else { return 0 }
        let bitCount = byteCount * 8
        let signBit = UInt64(1) << UInt64(bitCount - 1)
        if unsigned & signBit == 0 {
            return Int64(unsigned)
        }
        let fullRange = UInt64(1) << UInt64(bitCount)
        return Int64(bitPattern: unsigned) - Int64(bitPattern: fullRange)
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0 else {
            throw DVIError.malformed("invalid byte count \(count)")
        }
        guard offset + count <= data.count else {
            throw DVIError.malformed("unexpected end of file while reading bytes")
        }
        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    mutating func skip(_ count: Int) throws {
        _ = try readBytes(count)
    }
}
