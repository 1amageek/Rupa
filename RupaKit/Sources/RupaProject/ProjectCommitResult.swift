import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel

public struct ProjectCommitResult: Sendable {
    public let sourceRevision: DocumentTransactionRevision
    public let source: ProjectSourceModel
    public let evaluation: EvaluatedProjectSnapshot

    public init(
        sourceRevision: DocumentTransactionRevision,
        source: ProjectSourceModel,
        evaluation: EvaluatedProjectSnapshot
    ) {
        self.sourceRevision = sourceRevision
        self.source = source
        self.evaluation = evaluation
    }
}
