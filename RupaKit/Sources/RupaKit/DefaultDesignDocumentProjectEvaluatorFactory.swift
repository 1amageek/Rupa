import RupaCADIntegration
import RupaCore
import RupaEvaluation

/// The product composition that connects built-in mesh and Swift-CAD providers.
public struct DefaultDesignDocumentProjectEvaluatorFactory:
    DesignDocumentProjectEvaluatorFactory {
    /// The ceiling this product states for each representation purpose.
    ///
    /// The policy is the only seam through which the product narrows an
    /// evaluation, so the composition states it rather than inheriting the
    /// module default silently. It cannot widen what `RupaEvaluation` owns:
    /// `EvaluationResourcePolicy` refuses any limit above the module hard
    /// ceiling at construction.
    public let resourcePolicy: EvaluationResourcePolicy

    public init(resourcePolicy: EvaluationResourcePolicy = .standard) {
        self.resourcePolicy = resourcePolicy
    }

    public func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        if let currentEvaluation,
           !currentEvaluation.matches(
               document: document,
               generation: currentEvaluation.generation
           ) {
            throw DesignDocumentProjectBridgeError(
                code: .staleEvaluation,
                message: "The reusable CAD evaluation was produced from different source content."
            )
        }
        let configuration = CADGeometryEvaluationConfiguration(
            tolerance: document.modelingSettings.tolerance,
            tessellationOptions: try document.displayTessellationOptions()
        )
        let cadEvaluationCache = CADDocumentEvaluationCache()
        let registry = try GeometrySourceEvaluationProviderRegistry(
            providers: [
                MeshSourceEvaluationProvider(),
                CADGeometrySourceProvider(
                    document: document.cadDocument,
                    configuration: configuration,
                    cache: cadEvaluationCache
                ),
            ]
        )
        return DesignDocumentProjectEvaluator(
            evaluator: ProjectEvaluationEngine(
                registry: registry,
                policy: resourcePolicy
            ),
            cadEvaluationCache: cadEvaluationCache,
            cadConfiguration: configuration,
            reusableEvaluation: currentEvaluation
        )
    }
}
