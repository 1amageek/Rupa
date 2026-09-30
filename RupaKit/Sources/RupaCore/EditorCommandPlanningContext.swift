import Foundation
import RupaCoreTypes

/// Immutable state used while a source command is being planned.
public struct EditorCommandPlanningContext: Sendable {
    public let document: DesignDocument
    public let selection: SelectionModel
    public let objectRegistry: ObjectTypeRegistry
    public let evaluationSnapshot: EvaluationSnapshot
    /// The document's current evaluation at `generation`, read by planning that needs topology
    /// instead of evaluating the document again; nil when the caller has none.
    public let currentEvaluation: DocumentEvaluationContext?
    public let generation: DocumentGeneration?

    public init(
        document: DesignDocument,
        selection: SelectionModel,
        objectRegistry: ObjectTypeRegistry,
        evaluationSnapshot: EvaluationSnapshot,
        currentEvaluation: DocumentEvaluationContext?,
        generation: DocumentGeneration?
    ) {
        self.document = document
        self.selection = selection
        self.objectRegistry = objectRegistry
        self.evaluationSnapshot = evaluationSnapshot
        self.currentEvaluation = currentEvaluation
        self.generation = generation
    }
}
