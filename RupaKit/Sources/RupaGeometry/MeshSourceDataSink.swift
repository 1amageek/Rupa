import Foundation

struct MeshSourceDataSink: MeshSourceChunkSink {
    private(set) var data: Data

    init(reservingCapacity capacity: Int = 0) {
        data = Data()
        data.reserveCapacity(capacity)
    }

    mutating func write(_ chunk: borrowing Span<UInt8>) throws {
        chunk.withUnsafeBytes { bytes in
            // Data is the explicit owning output boundary. It copies the borrowed
            // chunk once while the span's owner remains alive for this closure.
            data.append(contentsOf: bytes)
        }
    }
}
