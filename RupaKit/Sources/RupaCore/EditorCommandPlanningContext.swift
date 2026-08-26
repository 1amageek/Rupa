import Foundation
import RupaCoreTypes

/// Immutable state used while a source command is being planned.
public struct EditorCommandPlanningContext: Sendable {
    public let document: DesignDocument
    public let selection: SelectionModel
    public let objectRegistry: ObjectTypeRegistry
    public let evaluationSnapshot: EvaluationSnapshot

    public init(
        document: DesignDocument,
        selection: SelectionModel,
        objectRegistry: ObjectTypeRegistry,
        evaluationSnapshot: EvaluationSnapshot
    ) {
        self.document = document
        self.selection = selection
        self.objectRegistry = objectRegistry
        self.evaluationSnapshot = evaluationSnapshot
    }
}
