import RupaCore
import RupaEvaluation

/// Creates an evaluator bound to one immutable authoritative document source.
public protocol ProjectEvaluatorPreparing: Sendable {
    func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating

    /// An evaluator for a document the caller already validated, which reads that validation
    /// (and the CAD source fingerprint it carries) instead of validating the document again.
    func makeEvaluator(
        for validatedDocument: ValidatedDesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating
}

public extension ProjectEvaluatorPreparing {
    /// A preparer that does not use the validation evaluates the document itself.
    func makeEvaluator(
        for validatedDocument: ValidatedDesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        try makeEvaluator(for: validatedDocument.document, reusing: currentEvaluation)
    }
}
