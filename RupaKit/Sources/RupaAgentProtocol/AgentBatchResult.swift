import RupaAutomation
import RupaCore

public struct AgentBatchResult: Codable, Equatable, Sendable {
    public var results: [AutomationResult]
    public var generation: DocumentGeneration
    public var dirty: Bool

    public init(
        results: [AutomationResult],
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.results = results
        self.generation = generation
        self.dirty = dirty
    }

    public var commandCount: Int {
        results.count
    }

    public var didMutate: Bool {
        results.contains { $0.didMutate }
    }
}
