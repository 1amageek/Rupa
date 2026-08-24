/// Receives bounded encoded mesh-source chunks during one synchronous call.
public protocol MeshSourceChunkSink {
    /// The borrowed span is valid only for this call and must not escape.
    mutating func write(_ chunk: borrowing Span<UInt8>) throws
}
