public struct DesignProcessRouteEvidence: Codable, Equatable, Sendable {
    public var sourceFiles: [String]
    public var tests: [DesignProcessTestReference]
    public var diagnostics: [String]
    public var notes: [String]

    public init(
        sourceFiles: [String] = [],
        tests: [DesignProcessTestReference] = [],
        diagnostics: [String] = [],
        notes: [String] = []
    ) {
        self.sourceFiles = sourceFiles
        self.tests = tests
        self.diagnostics = diagnostics
        self.notes = notes
    }
}
