public struct DesignProcessDiagnostic: Codable, Equatable, Sendable {
    public var id: String
    public var severity: DesignProcessObservationSeverity
    public var message: String
    public var affectedLayer: DesignProcessLayer
    public var source: String?

    public init(
        id: String,
        severity: DesignProcessObservationSeverity,
        message: String,
        affectedLayer: DesignProcessLayer,
        source: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.affectedLayer = affectedLayer
        self.source = source
    }
}
