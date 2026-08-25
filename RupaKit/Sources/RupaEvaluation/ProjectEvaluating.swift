import RupaCoreTypes
import RupaProjectModel

/// Evaluates an immutable project source at a specific source revision.
public protocol ProjectEvaluating: Sendable {
    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot
}
