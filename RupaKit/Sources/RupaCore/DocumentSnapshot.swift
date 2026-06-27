import Foundation
import RupaCoreTypes

public struct DocumentSnapshot: Sendable {
    public var document: DesignDocument
    public var generation: DocumentGeneration
    public var isDirty: Bool
    public var diagnostics: [EditorDiagnostic]
    public var evaluationStatus: EvaluationStatus
    public var evaluatedGeneration: DocumentGeneration?
    public var renderInvalidation: RenderInvalidation
    public var evaluatedBodyCount: Int

    public init(
        document: DesignDocument,
        generation: DocumentGeneration,
        isDirty: Bool,
        diagnostics: [EditorDiagnostic],
        evaluationStatus: EvaluationStatus,
        evaluatedGeneration: DocumentGeneration? = nil,
        renderInvalidation: RenderInvalidation = RenderInvalidation(),
        evaluatedBodyCount: Int = 0
    ) {
        self.document = document
        self.generation = generation
        self.isDirty = isDirty
        self.diagnostics = diagnostics
        self.evaluationStatus = evaluationStatus
        self.evaluatedGeneration = evaluatedGeneration
        self.renderInvalidation = renderInvalidation
        self.evaluatedBodyCount = evaluatedBodyCount
    }
}
