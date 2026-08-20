import RupaCoreTypes
import RupaProjectModel

/// Evaluates an immutable project source at a specific source revision.
public protocol ProjectEvaluating: Sendable {
    func evaluate(
        _ project: ProjectSourceModel,
        sourceRevision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot
}

public extension ProjectEvaluating {
    func evaluate(
        _ project: ProjectSourceModel
    ) throws -> EvaluatedProjectSnapshot {
        try evaluate(project, sourceRevision: DocumentTransactionRevision())
    }
}
