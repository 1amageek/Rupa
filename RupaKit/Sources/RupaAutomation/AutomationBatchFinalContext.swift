import RupaCore
import RupaCoreTypes

/// Immutable state observed after a staged Automation batch has run.
public struct AutomationBatchFinalContext: Sendable {
    public let document: DesignDocument
    public let generation: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let selection: SelectionModel
    public let workspaceState: WorkspaceState
    public let objectRegistry: ObjectTypeRegistry
    public let evaluationSnapshot: EvaluationSnapshot
    public let currentEvaluation: DocumentEvaluationContext?
    public let isDirty: Bool
    public let diagnostics: [EditorDiagnostic]

    public init(
        document: DesignDocument,
        generation: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        selection: SelectionModel,
        workspaceState: WorkspaceState,
        objectRegistry: ObjectTypeRegistry,
        evaluationSnapshot: EvaluationSnapshot,
        currentEvaluation: DocumentEvaluationContext?,
        isDirty: Bool,
        diagnostics: [EditorDiagnostic]
    ) {
        self.document = document
        self.generation = generation
        self.transactionRevision = transactionRevision
        self.selection = selection
        self.workspaceState = workspaceState
        self.objectRegistry = objectRegistry
        self.evaluationSnapshot = evaluationSnapshot
        self.currentEvaluation = currentEvaluation
        self.isDirty = isDirty
        self.diagnostics = diagnostics
    }

    public init(session: EditorSession) {
        self.init(
            document: session.document,
            generation: session.generation,
            transactionRevision: session.transactionRevision,
            selection: session.selection,
            workspaceState: session.workspaceState,
            objectRegistry: session.objectRegistry,
            evaluationSnapshot: session.evaluationSnapshot,
            currentEvaluation: session.currentEvaluation,
            isDirty: session.isDirty,
            diagnostics: EditorDiagnostic.stableMerged([
                session.diagnostics,
                session.evaluationSnapshot.diagnostics,
            ])
        )
    }

    init(
        copying context: AutomationBatchFinalContext,
        transactionRevision: DocumentTransactionRevision
    ) {
        self.init(
            document: context.document,
            generation: context.generation,
            transactionRevision: transactionRevision,
            selection: context.selection,
            workspaceState: context.workspaceState,
            objectRegistry: context.objectRegistry,
            evaluationSnapshot: context.evaluationSnapshot,
            currentEvaluation: context.currentEvaluation,
            isDirty: context.isDirty,
            diagnostics: context.diagnostics
        )
    }
}
