public struct DesignProcessRoute: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var source: DesignProcessRoutePort
    public var target: DesignProcessRoutePort
    public var status: DesignProcessRouteStatus
    public var evidence: DesignProcessRouteEvidence
    public var diagnostics: [DesignProcessDiagnostic]

    public init(
        id: String,
        title: String,
        source: DesignProcessRoutePort,
        target: DesignProcessRoutePort,
        status: DesignProcessRouteStatus,
        evidence: DesignProcessRouteEvidence = DesignProcessRouteEvidence(),
        diagnostics: [DesignProcessDiagnostic] = []
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.target = target
        self.status = status
        self.evidence = evidence
        self.diagnostics = diagnostics
    }
}
