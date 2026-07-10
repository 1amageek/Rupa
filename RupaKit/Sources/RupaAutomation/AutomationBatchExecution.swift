import RupaCore
import RupaCoreTypes

public struct AutomationBatchExecution: Sendable {
    public var results: [AutomationResult]
    public var effect: AutomationCommandEffect
    public var baseGeneration: DocumentGeneration
    public var proposedGeneration: DocumentGeneration
    public var baseWorkspaceRevision: WorkspaceRevision
    public var proposedWorkspaceRevision: WorkspaceRevision
    public var didCommit: Bool

    public init(
        results: [AutomationResult],
        effect: AutomationCommandEffect,
        baseGeneration: DocumentGeneration,
        proposedGeneration: DocumentGeneration,
        baseWorkspaceRevision: WorkspaceRevision,
        proposedWorkspaceRevision: WorkspaceRevision,
        didCommit: Bool
    ) {
        self.results = results
        self.effect = effect
        self.baseGeneration = baseGeneration
        self.proposedGeneration = proposedGeneration
        self.baseWorkspaceRevision = baseWorkspaceRevision
        self.proposedWorkspaceRevision = proposedWorkspaceRevision
        self.didCommit = didCommit
    }
}
