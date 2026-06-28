public struct DesignProcessCalibrationAnchor: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var channel: DesignProcessObservationChannel
    public var affectedLayer: DesignProcessLayer
    public var state: DesignProcessCalibrationState
    public var summary: String
    public var evidence: [String]

    public init(
        id: String,
        title: String,
        channel: DesignProcessObservationChannel,
        affectedLayer: DesignProcessLayer,
        state: DesignProcessCalibrationState,
        summary: String,
        evidence: [String] = []
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.affectedLayer = affectedLayer
        self.state = state
        self.summary = summary
        self.evidence = evidence
    }
}
