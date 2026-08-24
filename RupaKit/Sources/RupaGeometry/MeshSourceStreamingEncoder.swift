public protocol MeshSourceStreamingEncoder: Sendable {
    func encode<Sink: MeshSourceChunkSink>(
        _ source: MeshSource,
        to sink: inout Sink,
        limits: MeshSourceCodecLimits,
        telemetry: inout GeometryCopyTelemetry
    ) throws
}
