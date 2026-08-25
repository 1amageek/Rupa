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
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        if let reusableEvaluation {
            try cadEvaluationCache.seed(
                validatedDocument: reusableEvaluation.validatedDocument.validatedCADDocument,
                evaluatedDocument: reusableEvaluation.evaluatedDocument,
                sourceRevision: revision,
                configuration: cadConfiguration
            )
        }
        return try evaluator.evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}
