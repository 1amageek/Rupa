import Foundation

struct ProjectPackageByteCursor {
    private let data: Data
    private let upperBound: Int
    private(set) var offset: Int

    init(data: Data, offset: Int = 0, upperBound: Int? = nil) throws {
        let limit = upperBound ?? data.count
        guard offset >= 0, limit >= offset, limit <= data.count else {
            throw Self.malformed("Project package byte range is invalid.")
        }
        self.data = data
        self.offset = offset
        self.upperBound = limit
    }

    mutating func readUInt16() throws -> UInt16 {
        try require(2)
        let result = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        offset += 2
        return result
    }

    mutating func readUInt32() throws -> UInt32 {
        try require(4)
        let result = UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
        offset += 4
        return result
    }

    mutating func readUTF8(byteCount: Int) throws -> String {
        try require(byteCount)
        let range = offset..<(offset + byteCount)
        let value = data.withUnsafeBytes { rawBytes -> String? in
            // The cursor validated the range and Data retains its immutable owner.
            // The raw view is used only for this bounded UTF-8 metadata conversion.
            let bytes = UnsafeRawBufferPointer(rebasing: rawBytes[range])
            return String(bytes: bytes, encoding: .utf8)
        }
        guard let value else {
            throw Self.malformed("Project package path is not valid UTF-8.")
        }
        offset += byteCount
        return value
    }

    mutating func skip(_ byteCount: Int) throws {
        try require(byteCount)
        offset += byteCount
    }

    static func uint32(in data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else {
            return nil
        }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private func require(_ byteCount: Int) throws {
        guard byteCount >= 0, offset <= upperBound - byteCount else {
            throw Self.malformed("Project package archive is truncated.")
        }
    }

    private static func malformed(_ message: String) -> ProjectPackageError {
        ProjectPackageError(code: .malformedArchive, message: message)
    }
}
