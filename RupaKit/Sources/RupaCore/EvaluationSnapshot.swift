import Foundation

public struct EvaluationSnapshot: Codable, Equatable, Sendable {
    public var status: EvaluationStatus
    public var evaluatedGeneration: DocumentGeneration?
    public var renderInvalidation: RenderInvalidation
    public var bodyCount: Int
    public var diagnostics: [RupaDiagnostic]

    public init(
        status: EvaluationStatus = .notEvaluated,
        evaluatedGeneration: DocumentGeneration? = nil,
        renderInvalidation: RenderInvalidation = RenderInvalidation(),
        bodyCount: Int = 0,
        diagnostics: [RupaDiagnostic] = []
    ) {
        self.status = status
        self.evaluatedGeneration = evaluatedGeneration
        self.renderInvalidation = renderInvalidation
        self.bodyCount = bodyCount
        self.diagnostics = diagnostics
    }
}
