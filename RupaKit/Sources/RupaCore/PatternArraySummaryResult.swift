import RupaCoreTypes
public struct PatternArraySummaryResult: Codable, Equatable, Sendable {
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var patternArrays: [PatternArraySummary]

    public init(
        generation: DocumentGeneration,
        dirty: Bool,
        patternArrays: [PatternArraySummary]
    ) {
        self.generation = generation
        self.dirty = dirty
        self.patternArrays = patternArrays
    }
}
