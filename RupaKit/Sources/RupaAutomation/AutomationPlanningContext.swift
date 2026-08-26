import RupaCore
import RupaCoreTypes

/// Immutable project state used to prepare an Automation batch for staging.
public struct AutomationPlanningContext: Sendable {
    public let document: DesignDocument
    public let generation: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let selection: SelectionModel
    public let workspaceState: WorkspaceState
    public let objectRegistry: ObjectTypeRegistry
    public let evaluationSnapshot: EvaluationSnapshot
    public let currentEvaluation: DocumentEvaluationContext?

    public init(
        document: DesignDocument,
        generation: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        selection: SelectionModel,
        workspaceState: WorkspaceState,
        objectRegistry: ObjectTypeRegistry,
        evaluationSnapshot: EvaluationSnapshot,
        currentEvaluation: DocumentEvaluationContext?
    ) {
        self.document = document
        self.generation = generation
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.selection = selection
        self.workspaceState = workspaceState
        self.objectRegistry = objectRegistry
        self.evaluationSnapshot = evaluationSnapshot
        self.currentEvaluation = currentEvaluation
    }
}
