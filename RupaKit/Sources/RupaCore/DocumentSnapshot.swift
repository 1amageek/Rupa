import Foundation

public struct DocumentSnapshot: Sendable {
    public var document: RupaDocument
    public var generation: DocumentGeneration
    public var isDirty: Bool
    public var diagnostics: [RupaDiagnostic]
    public var evaluationStatus: EvaluationStatus
    public var evaluatedGeneration: DocumentGeneration?
    public var renderInvalidation: RenderInvalidation
    public var evaluatedBodyCount: Int

    public init(
        document: RupaDocument,
        generation: DocumentGeneration,
        isDirty: Bool,
        diagnostics: [RupaDiagnostic],
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
