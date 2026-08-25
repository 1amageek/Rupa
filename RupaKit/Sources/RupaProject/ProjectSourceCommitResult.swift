import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectPackage

public struct ProjectSourceCommitResult: Sendable {
    public let baseTransactionRevision: DocumentTransactionRevision
    public let transactionRevision: DocumentTransactionRevision
    public let documentGeneration: DocumentGeneration
    public let document: DesignDocument
    public let package: ProjectPackageDocument
    public let evaluation: EvaluatedProjectSnapshot
    public let commandResults: [CommandExecutionResult]
    public let geometrySourceCommandResults: [GeometrySourceCommandResult]

    public init(
        baseTransactionRevision: DocumentTransactionRevision,
        transactionRevision: DocumentTransactionRevision,
        documentGeneration: DocumentGeneration,
        document: DesignDocument,
        package: ProjectPackageDocument,
        evaluation: EvaluatedProjectSnapshot,
        commandResults: [CommandExecutionResult],
        geometrySourceCommandResults: [GeometrySourceCommandResult]
    ) {
        self.baseTransactionRevision = baseTransactionRevision
        self.transactionRevision = transactionRevision
        self.documentGeneration = documentGeneration
        self.document = document
        self.package = package
        self.evaluation = evaluation
        self.commandResults = commandResults
        self.geometrySourceCommandResults = geometrySourceCommandResults
    }
}
