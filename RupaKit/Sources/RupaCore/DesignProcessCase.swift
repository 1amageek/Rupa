public struct DesignProcessCase: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: DesignProcessCaseStatus
    public var diagnostic: DesignProcessDiagnostic?
    public var testReferences: [DesignProcessTestReference]
    public var evidence: [String]
    public var notes: [String]

    public init(
        id: String,
        title: String,
        status: DesignProcessCaseStatus,
        diagnostic: DesignProcessDiagnostic? = nil,
        testReferences: [DesignProcessTestReference] = [],
        evidence: [String] = [],
        notes: [String] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.diagnostic = diagnostic
        self.testReferences = testReferences
        self.evidence = evidence
        self.notes = notes
    }
}
