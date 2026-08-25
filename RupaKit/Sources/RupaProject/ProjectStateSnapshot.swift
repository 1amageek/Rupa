import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectPackage

public struct ProjectStateSnapshot: Sendable {
    public let document: DesignDocument
    public let package: ProjectPackageDocument
    public let transactionRevision: DocumentTransactionRevision
    public let evaluation: EvaluatedProjectSnapshot

    public init(
        document: DesignDocument,
        package: ProjectPackageDocument,
        transactionRevision: DocumentTransactionRevision,
        evaluation: EvaluatedProjectSnapshot
    ) {
        self.document = document
        self.package = package
        self.transactionRevision = transactionRevision
        self.evaluation = evaluation
    }
}
