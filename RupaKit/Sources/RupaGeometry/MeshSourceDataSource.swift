import Foundation

struct MeshSourceDataSource: MeshSourceChunkSource {
    private let data: Data
    private var offset: Int

    init(data: Data) {
        self.data = data
        offset = 0
    }

    mutating func read(into buffer: inout MutableSpan<UInt8>) throws -> Int {
        let copiedByteCount = min(buffer.count, data.count - offset)
        guard copiedByteCount > 0 else {
            return 0
        }
        data.withUnsafeBytes { sourceBytes in
            buffer.withUnsafeMutableBytes { destinationBytes in
                // Data owns the source bytes and the codec owns the destination span.
                // Both pointers are confined to these borrows and ranges are validated.
                let source = UnsafeRawBufferPointer(
                    start: sourceBytes.baseAddress?.advanced(by: offset),
                    count: copiedByteCount
                )
                destinationBytes.copyMemory(from: source)
            }
        }
        offset += copiedByteCount
        return copiedByteCount
    }
}
