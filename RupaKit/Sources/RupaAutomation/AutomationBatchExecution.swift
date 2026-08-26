import RupaCore
import RupaCoreTypes

public struct AutomationBatchExecution: Sendable {
    public var results: [AutomationResult]
    public var effect: AutomationCommandEffect
    public var baseGeneration: DocumentGeneration
    public var proposedGeneration: DocumentGeneration
    public var baseTransactionRevision: DocumentTransactionRevision
    public var proposedTransactionRevision: DocumentTransactionRevision
    public var baseWorkspaceRevision: WorkspaceRevision
    public var proposedWorkspaceRevision: WorkspaceRevision
    public var didCommit: Bool
    public var metrics: AutomationBatchMetrics
    public var finalContext: AutomationBatchFinalContext

    public init(
        results: [AutomationResult],
        effect: AutomationCommandEffect,
        baseGeneration: DocumentGeneration,
        proposedGeneration: DocumentGeneration,
        baseTransactionRevision: DocumentTransactionRevision,
        proposedTransactionRevision: DocumentTransactionRevision,
        baseWorkspaceRevision: WorkspaceRevision,
        proposedWorkspaceRevision: WorkspaceRevision,
        didCommit: Bool,
        metrics: AutomationBatchMetrics,
        finalContext: AutomationBatchFinalContext
    ) {
        self.results = results
        self.effect = effect
        self.baseGeneration = baseGeneration
        self.proposedGeneration = proposedGeneration
        self.baseTransactionRevision = baseTransactionRevision
        self.proposedTransactionRevision = proposedTransactionRevision
        self.baseWorkspaceRevision = baseWorkspaceRevision
        self.proposedWorkspaceRevision = proposedWorkspaceRevision
        self.didCommit = didCommit
        self.metrics = metrics
        self.finalContext = finalContext
    }

    /// Feature IDs produced by the commands, retaining command order and removing duplicates.
    public var generatedFeatureIDs: [FeatureID] {
        var generated: [FeatureID] = []
        for featureID in results.flatMap(\.createdFeatureIDs)
            where !generated.contains(featureID) {
            generated.append(featureID)
        }
        return generated
    }

    /// Diagnostics returned by commands plus diagnostics observed in the final staged context.
    public var diagnostics: [EditorDiagnostic] {
        EditorDiagnostic.stableMerged([
            results.flatMap(\.diagnostics),
            finalContext.diagnostics,
        ])
    }
}
