import RupaCore
import RupaEvaluation

/// Creates the project evaluator composition required by a design document.
public protocol DesignDocumentProjectEvaluatorFactory: Sendable {
    /// The reusable evaluation must describe the same immutable document source.
    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating
}
