import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaProjectPackage

public struct ProjectStateSnapshot: Sendable {
    public let document: DesignDocument
    public let package: ProjectPackageDocument
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let isDirty: Bool
    public let selection: SelectionModel
    public let workspaceState: WorkspaceState
    public let evaluationSource: ProjectSourceModel
    public let cadInteraction: DocumentEvaluationContext?
    public let evaluation: EvaluatedProjectSnapshot

    public init(
        document: DesignDocument,
        package: ProjectPackageDocument,
        documentGeneration: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        isDirty: Bool,
        selection: SelectionModel,
        workspaceState: WorkspaceState,
        evaluationSource: ProjectSourceModel,
        cadInteraction: DocumentEvaluationContext?,
        evaluation: EvaluatedProjectSnapshot
    ) {
        self.document = document
        self.package = package
        self.documentGeneration = documentGeneration
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.isDirty = isDirty
        self.selection = selection
        self.workspaceState = workspaceState
        self.evaluationSource = evaluationSource
        self.cadInteraction = cadInteraction
        self.evaluation = evaluation
    }
}
