import RupaAutomation
import RupaCore

public struct AgentBatchResult: Codable, Equatable, Sendable {
    public var results: [AutomationResult]
    public var generation: DocumentGeneration
    public var workspaceRevision: WorkspaceRevision
    public var dirty: Bool
    public var metrics: AutomationBatchMetrics

    public init(
        results: [AutomationResult],
        generation: DocumentGeneration,
        workspaceRevision: WorkspaceRevision,
        dirty: Bool,
        metrics: AutomationBatchMetrics
    ) {
        self.results = results
        self.generation = generation
        self.workspaceRevision = workspaceRevision
        self.dirty = dirty
        self.metrics = metrics
    }

    public var commandCount: Int {
        results.count
    }

    public var didMutate: Bool {
        results.contains { $0.didMutate }
    }
}
