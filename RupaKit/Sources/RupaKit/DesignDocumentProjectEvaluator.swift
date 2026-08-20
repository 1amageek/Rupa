import RupaCADIntegration
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaProjectModel

/// Seeds current CAD state before delegating to the universal project evaluator.
struct DesignDocumentProjectEvaluator: ProjectEvaluating {
    private let evaluator: any ProjectEvaluating
    private let cadEvaluationCache: CADDocumentEvaluationCache
    private let cadConfiguration: CADGeometryEvaluationConfiguration
    private let reusableEvaluation: DocumentEvaluationContext?

    init(
        evaluator: any ProjectEvaluating,
        cadEvaluationCache: CADDocumentEvaluationCache,
        cadConfiguration: CADGeometryEvaluationConfiguration,
        reusableEvaluation: DocumentEvaluationContext?
    ) {
        self.evaluator = evaluator
        self.cadEvaluationCache = cadEvaluationCache
        self.cadConfiguration = cadConfiguration
        self.reusableEvaluation = reusableEvaluation
    }

    func evaluate(
        _ project: ProjectSourceModel,
        sourceRevision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        if let reusableEvaluation {
            guard sourceRevision.value == reusableEvaluation.generation.value else {
                throw DesignDocumentProjectBridgeError(
                    code: .staleEvaluation,
                    message: "The reusable CAD evaluation generation does not match the requested source revision."
                )
            }
            try cadEvaluationCache.seed(
                validatedDocument: reusableEvaluation.validatedDocument.validatedCADDocument,
                evaluatedDocument: reusableEvaluation.evaluatedDocument,
                sourceRevision: sourceRevision,
                configuration: cadConfiguration
            )
        }
        return try evaluator.evaluate(
            project,
            sourceRevision: sourceRevision
        )
    }
}
