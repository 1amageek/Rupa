import RupaCADIntegration
import RupaCore
import RupaEvaluation

/// The product composition that connects built-in mesh and Swift-CAD providers.
public struct DefaultDesignDocumentProjectEvaluatorFactory:
    DesignDocumentProjectEvaluatorFactory {
    private let cadEvaluationCache: CADDocumentEvaluationCache

    public init(
        cadEvaluationCache: CADDocumentEvaluationCache = CADDocumentEvaluationCache()
    ) {
        self.cadEvaluationCache = cadEvaluationCache
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
            tessellationOptions: document.modelingSettings.tessellationOptions
        )
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
            evaluator: ProjectEvaluationEngine(registry: registry),
            cadEvaluationCache: cadEvaluationCache,
            cadConfiguration: configuration,
            reusableEvaluation: currentEvaluation
        )
    }
}
