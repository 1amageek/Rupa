import Foundation

public enum MeshSourceCodec {
    public static func encode(_ source: MeshSource) throws -> Data {
        var telemetry = GeometryCopyTelemetry()
        return try encode(source, limits: .standard, telemetry: &telemetry)
    }

    public static func encode(
        _ source: MeshSource,
        limits: MeshSourceCodecLimits,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> Data {
        let capacity = try MeshSourceBinarySizeCalculator.encodedByteCount(
            of: source,
            limits: limits
        )
        guard let exactCapacity = Int(exactly: capacity) else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message: "Mesh source blob exceeds the platform Data capacity."
            )
        }
        var sink = MeshSourceDataSink(reservingCapacity: exactCapacity)
        try BinaryMeshSourceCodec().encode(
            source,
            to: &sink,
            limits: limits,
            telemetry: &telemetry
        )
        return sink.data
    }

    public static func encode<Sink: MeshSourceChunkSink>(
        _ source: MeshSource,
        to sink: inout Sink,
        limits: MeshSourceCodecLimits = .standard,
        telemetry: inout GeometryCopyTelemetry
    ) throws {
        try BinaryMeshSourceCodec().encode(
            source,
            to: &sink,
            limits: limits,
            telemetry: &telemetry
        )
    }

    public static func decode(_ data: Data) throws -> MeshSource {
        var telemetry = GeometryCopyTelemetry()
        return try decode(data, limits: .standard, telemetry: &telemetry)
    }

    public static func decode(
        _ data: Data,
        limits: MeshSourceCodecLimits,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> MeshSource {
        var source = MeshSourceDataSource(data: data)
        return try BinaryMeshSourceCodec().decode(
            from: &source,
            limits: limits,
            telemetry: &telemetry
        )
    }

    public static func decode<Source: MeshSourceChunkSource>(
        from source: inout Source,
        limits: MeshSourceCodecLimits = .standard,
        telemetry: inout GeometryCopyTelemetry
    ) throws -> MeshSource {
        try BinaryMeshSourceCodec().decode(
            from: &source,
            limits: limits,
            telemetry: &telemetry
        )
    }
}
