protocol ProjectPackageByteSink {
    var writtenByteCount: UInt64 { get }
    var maximumWrittenChunkByteCount: Int { get }

    mutating func write(_ bytes: borrowing Span<UInt8>) throws
}
