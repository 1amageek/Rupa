public struct MeshEditCommitResult: Sendable {
    public let source: MeshSource
    public let telemetry: GeometryCopyTelemetry

    public init(source: MeshSource, telemetry: GeometryCopyTelemetry) {
        self.source = source
        self.telemetry = telemetry
    }
}
