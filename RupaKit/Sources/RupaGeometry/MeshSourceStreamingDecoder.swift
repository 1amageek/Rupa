public protocol MeshSourceStreamingDecoder: Sendable {
    func decode<Source: MeshSourceChunkSource>(
        from source: inout Source,
        limits: MeshSourceCodecLimits,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> MeshSource
}
