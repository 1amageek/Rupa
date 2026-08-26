import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaProjectPackage

public struct ProjectStateSnapshot: Sendable {
    public let documentLifetimeID: ProjectDocumentLifetimeID
    public let document: DesignDocument
    public let package: ProjectPackageDocument
    public let documentGeneration: DocumentGeneration
    public let transactionRevision: DocumentTransactionRevision
    public let publicationSequence: UInt64
    public let isDirty: Bool
    public let canUndo: Bool
    public let canRedo: Bool
    public let selection: SelectionModel
    public let workspaceState: WorkspaceState
    public let objectRegistry: ObjectTypeRegistry
    public let evaluationSnapshot: EvaluationSnapshot
    public let evaluationSource: ProjectSourceModel
    public let cadInteraction: DocumentEvaluationContext?
    public let evaluation: EvaluatedProjectSnapshot

    public init(
        documentLifetimeID: ProjectDocumentLifetimeID,
        document: DesignDocument,
        package: ProjectPackageDocument,
        documentGeneration: DocumentGeneration,
        transactionRevision: DocumentTransactionRevision,
        publicationSequence: UInt64,
        isDirty: Bool,
        canUndo: Bool,
        canRedo: Bool,
        selection: SelectionModel,
        workspaceState: WorkspaceState,
        objectRegistry: ObjectTypeRegistry,
        evaluationSnapshot: EvaluationSnapshot,
        evaluationSource: ProjectSourceModel,
        cadInteraction: DocumentEvaluationContext?,
        evaluation: EvaluatedProjectSnapshot
    ) {
        self.documentLifetimeID = documentLifetimeID
        self.document = document
        self.package = package
        self.documentGeneration = documentGeneration
        self.transactionRevision = transactionRevision
        self.publicationSequence = publicationSequence
        self.isDirty = isDirty
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.selection = selection
        self.workspaceState = workspaceState
        self.objectRegistry = objectRegistry
        self.evaluationSnapshot = evaluationSnapshot
        self.evaluationSource = evaluationSource
        self.cadInteraction = cadInteraction
        self.evaluation = evaluation
    }
}
