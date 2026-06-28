public struct DesignProcessValidatedArtifact: Codable, Equatable, Sendable {
    public var sourceFiles: [String]
    public var tests: [DesignProcessTestReference]
    public var buildCommands: [String]
    public var diagnostics: [String]
    public var supportedClaims: [String]

    public init(
        sourceFiles: [String] = [],
        tests: [DesignProcessTestReference] = [],
        buildCommands: [String] = [],
        diagnostics: [String] = [],
        supportedClaims: [String] = []
    ) {
        self.sourceFiles = sourceFiles
        self.tests = tests
        self.buildCommands = buildCommands
        self.diagnostics = diagnostics
        self.supportedClaims = supportedClaims
    }
}
