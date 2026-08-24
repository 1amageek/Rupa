import Foundation

struct MeshSourceBinaryReader<Source: MeshSourceChunkSource> {
    var source: Source
    private var buffer: ContiguousArray<UInt8>
    private var bufferedByteCount: Int
    private var bufferOffset: Int
    private(set) var consumedByteCount: UInt64
    private var expectedTotalByteCount: UInt64?

    init(source: Source, chunkByteCount: Int) {
        self.source = source
        buffer = ContiguousArray(repeating: 0, count: chunkByteCount)
        bufferedByteCount = 0
        bufferOffset = 0
        consumedByteCount = 0
        expectedTotalByteCount = nil
    }

    mutating func setBodyByteCount(
        _ bodyByteCount: UInt64,
        limits: MeshSourceCodecLimits
    ) throws {
        let total = MeshSourceBinaryFormat.headerByteCount.addingReportingOverflow(
            bodyByteCount
        )
        guard !total.overflow,
            total.partialValue <= limits.maximumBlobByteCount
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source blob exceeds its configured byte limit."
            )
        }
        expectedTotalByteCount = total.partialValue
    }

    mutating func readByte() throws -> UInt8 {
        if let expectedTotalByteCount,
            consumedByteCount >= expectedTotalByteCount
        {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source body ended before its declared values were decoded."
            )
        }
        if bufferOffset == bufferedByteCount {
            try refill()
        }
        guard bufferOffset < bufferedByteCount else {
            throw MeshSourceError(
                code: .truncatedPayload,
                message: "Mesh source blob ended before the declared frame was complete."
            )
        }
        let byte = buffer[bufferOffset]
        bufferOffset += 1
        consumedByteCount += 1
        return byte
    }

    mutating func readUInt16() throws -> UInt16 {
        var value: UInt16 = 0
        for shift in stride(from: 0, to: 16, by: 8) {
            value |= UInt16(try readByte()) << UInt16(shift)
        }
        return value
    }

    mutating func readUInt32() throws -> UInt32 {
        var value: UInt32 = 0
        for shift in stride(from: 0, to: 32, by: 8) {
            value |= UInt32(try readByte()) << UInt32(shift)
        }
        return value
    }

    mutating func readUInt64() throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 8) {
            value |= UInt64(try readByte()) << UInt64(shift)
        }
        return value
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    mutating func readDouble() throws -> Double {
        Double(bitPattern: try readUInt64())
    }

    mutating func readString(limits: MeshSourceCodecLimits) throws -> String {
        let byteCount = Int(try readUInt32())
        guard byteCount <= limits.maximumStringByteCount else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source string exceeds its configured byte limit."
            )
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(byteCount)
        for _ in 0..<byteCount {
            bytes.append(try readByte())
        }
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source strings must contain valid UTF-8."
            )
        }
        return string
    }

    mutating func readBufferCount(limits: MeshSourceCodecLimits) throws -> Int {
        let encodedCount = try readUInt64()
        guard encodedCount <= UInt64(limits.maximumElementCountPerBuffer),
            let count = Int(exactly: encodedCount)
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source buffer exceeds its configured element limit."
            )
        }
        return count
    }

    mutating func finishFrame() throws {
        guard let expectedTotalByteCount,
            consumedByteCount == expectedTotalByteCount
        else {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source body length does not match its decoded values."
            )
        }
        if bufferOffset < bufferedByteCount {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source blob contains trailing bytes."
            )
        }
        try refill()
        guard bufferedByteCount == 0 else {
            throw MeshSourceError(
                code: .malformedPayload,
                message: "Mesh source blob contains trailing bytes."
            )
        }
    }

    private mutating func refill() throws {
        bufferOffset = 0
        do {
            bufferedByteCount = try buffer.withUnsafeMutableBufferPointer { pointer in
                // The ContiguousArray owns aligned, initialized UInt8 storage. MutableSpan
                // is confined to this closure and the source may initialize only its range.
                var span = MutableSpan(_unsafeElements: pointer)
                return try source.read(into: &span)
            }
        } catch {
            throw MeshSourceError(
                code: .ioFailure,
                message: "Mesh source input failed: \(error.localizedDescription)"
            )
        }
        guard bufferedByteCount >= 0,
            bufferedByteCount <= buffer.count
        else {
            throw MeshSourceError(
                code: .ioFailure,
                message: "Mesh source input returned an invalid chunk length."
            )
        }
    }
}
