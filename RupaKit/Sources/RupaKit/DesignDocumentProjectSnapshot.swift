import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel
import RupaViewportScene

public struct DesignDocumentProjectSnapshot: Sendable {
    public let documentGeneration: DocumentGeneration
    public let sourceRevision: DocumentTransactionRevision
    public let source: ProjectSourceModel
    public let evaluation: EvaluatedProjectSnapshot
    public let viewport: UniversalViewportScene

    public init(
        documentGeneration: DocumentGeneration,
        sourceRevision: DocumentTransactionRevision,
        source: ProjectSourceModel,
        evaluation: EvaluatedProjectSnapshot,
        viewport: UniversalViewportScene
    ) {
        self.documentGeneration = documentGeneration
        self.sourceRevision = sourceRevision
        self.source = source
        self.evaluation = evaluation
        self.viewport = viewport
    }
}
