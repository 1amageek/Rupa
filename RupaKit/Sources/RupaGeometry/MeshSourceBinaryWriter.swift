import Foundation

struct MeshSourceBinaryWriter<Sink: MeshSourceChunkSink> {
    var sink: Sink
    private var buffer: ContiguousArray<UInt8>
    private var bufferedByteCount: Int
    private(set) var writtenByteCount: UInt64

    init(sink: Sink, chunkByteCount: Int) {
        self.sink = sink
        buffer = ContiguousArray(repeating: 0, count: chunkByteCount)
        bufferedByteCount = 0
        writtenByteCount = 0
    }

    mutating func writeByte(_ value: UInt8) throws {
        buffer[bufferedByteCount] = value
        bufferedByteCount += 1
        if bufferedByteCount == buffer.count {
            try flush()
        }
    }

    mutating func writeBytes<Bytes: Sequence>(_ bytes: Bytes) throws
    where Bytes.Element == UInt8 {
        for byte in bytes {
            try writeByte(byte)
        }
    }

    mutating func writeUInt16(_ value: UInt16) throws {
        try writeByte(UInt8(truncatingIfNeeded: value))
        try writeByte(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func writeUInt32(_ value: UInt32) throws {
        for shift in stride(from: 0, to: 32, by: 8) {
            try writeByte(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func writeUInt64(_ value: UInt64) throws {
        for shift in stride(from: 0, to: 64, by: 8) {
            try writeByte(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    mutating func writeInt32(_ value: Int32) throws {
        try writeUInt32(UInt32(bitPattern: value))
    }

    mutating func writeFloat(_ value: Float) throws {
        let canonicalValue: Float = value == 0 ? 0 : value
        try writeUInt32(canonicalValue.bitPattern)
    }

    mutating func writeDouble(_ value: Double) throws {
        let canonicalValue: Double = value == 0 ? 0 : value
        try writeUInt64(canonicalValue.bitPattern)
    }

    mutating func writeString(_ value: String) throws {
        try writeUInt32(UInt32(value.utf8.count))
        try writeBytes(value.utf8)
    }

    mutating func finish() throws {
        try flush()
    }

    private mutating func flush() throws {
        guard bufferedByteCount > 0 else {
            return
        }
        let emittedByteCount = bufferedByteCount
        do {
            try buffer.withUnsafeBufferPointer { pointer in
                // The ContiguousArray is the initialized UInt8 owner. The span covers only
                // its validated prefix, is borrowed synchronously, and cannot escape `write`.
                let span = Span(_unsafeElements: pointer).extracting(0..<emittedByteCount)
                try sink.write(span)
            }
        } catch {
            throw MeshSourceError(
                code: .ioFailure,
                message: "Mesh source output failed: \(error.localizedDescription)"
            )
        }
        let addition = writtenByteCount.addingReportingOverflow(UInt64(emittedByteCount))
        guard !addition.overflow else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Encoded mesh source size exceeded UInt64."
            )
        }
        writtenByteCount = addition.partialValue
        bufferedByteCount = 0
    }
}
