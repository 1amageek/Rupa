public struct CADInteractionQualityEvidence: Codable, Equatable, Sendable {
    public var label: String
    public var sourceFiles: [String]
    public var tests: [String]
    public var notes: [String]

    public init(
        label: String,
        sourceFiles: [String] = [],
        tests: [String] = [],
        notes: [String] = []
    ) {
        self.label = label
        self.sourceFiles = sourceFiles
        self.tests = tests
        self.notes = notes
    }
}
