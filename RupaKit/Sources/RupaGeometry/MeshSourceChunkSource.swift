/// Supplies encoded mesh-source bytes through caller-owned reusable storage.
public protocol MeshSourceChunkSource {
    /// Writes at most `buffer.count` bytes and returns zero only at end of input.
    mutating func read(into buffer: inout MutableSpan<UInt8>) throws -> Int
}
