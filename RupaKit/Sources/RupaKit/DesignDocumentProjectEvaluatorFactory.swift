import RupaCore
import RupaEvaluation
import RupaProject

/// Creates the project evaluator composition required by a design document.
public protocol DesignDocumentProjectEvaluatorFactory: ProjectEvaluatorPreparing {
    /// The reusable evaluation must describe the same immutable document source.
    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating
}

public extension DesignDocumentProjectEvaluatorFactory {
    func makeEvaluator(
        for document: DesignDocument
    ) throws -> any ProjectEvaluating {
        try makeEvaluator(for: document, reusing: nil)
    }
}
