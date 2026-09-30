import RupaCADIntegration
import RupaCore
import RupaEvaluation
import SwiftCAD

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
    private let conversionCache = CADMeshSourceConversionCache()

    public init(resourcePolicy: EvaluationResourcePolicy = .standard) {
        self.resourcePolicy = resourcePolicy
    }

    public func makeEvaluator(
        for document: DesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        try makeEvaluator(for: document, validatedCADDocument: nil, reusing: currentEvaluation)
    }

    /// The CAD provider reads the caller's validated CAD document, so a candidate the project
    /// already validated is neither validated nor hashed again.
    public func makeEvaluator(
        for validatedDocument: ValidatedDesignDocument,
        reusing currentEvaluation: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        try makeEvaluator(
            for: validatedDocument.document,
            validatedCADDocument: validatedDocument.validatedCADDocument,
            reusing: currentEvaluation
        )
    }

    private func makeEvaluator(
        for document: DesignDocument,
        validatedCADDocument: ValidatedCADDocument?,
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
        var cadProvider = if let validatedCADDocument {
            CADGeometrySourceProvider(
                validatedDocument: validatedCADDocument,
                configuration: configuration,
                cache: cadEvaluationCache
            )
        } else {
            CADGeometrySourceProvider(
                document: document.cadDocument,
                configuration: configuration,
                cache: cadEvaluationCache
            )
        }
        cadProvider.conversionCache = conversionCache
        let registry = try GeometrySourceEvaluationProviderRegistry(
            providers: [
                MeshSourceEvaluationProvider(),
                cadProvider,
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
