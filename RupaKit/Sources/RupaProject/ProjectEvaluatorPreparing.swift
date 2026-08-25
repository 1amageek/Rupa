import RupaCore
import RupaEvaluation

/// Creates an evaluator bound to one immutable authoritative document source.
public protocol ProjectEvaluatorPreparing: Sendable {
    func makeEvaluator(
        for document: DesignDocument
    ) throws -> any ProjectEvaluating
}
