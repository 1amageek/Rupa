public struct DesignProcessObservation: Codable, Equatable, Sendable {
    public var id: String
    public var channel: DesignProcessObservationChannel
    public var severity: DesignProcessObservationSeverity
    public var affectedLayer: DesignProcessLayer
    public var summary: String
    public var requiredNextAction: String

    public init(
        id: String,
        channel: DesignProcessObservationChannel,
        severity: DesignProcessObservationSeverity,
        affectedLayer: DesignProcessLayer,
        summary: String,
        requiredNextAction: String
    ) {
        self.id = id
        self.channel = channel
        self.severity = severity
        self.affectedLayer = affectedLayer
        self.summary = summary
        self.requiredNextAction = requiredNextAction
    }
}
