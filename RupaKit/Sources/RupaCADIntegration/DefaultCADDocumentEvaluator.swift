import SwiftCAD

/// The production Swift-CAD evaluator used by the universal CAD provider.
public struct DefaultCADDocumentEvaluator: CADDocumentEvaluating {
    public let configuration: CADGeometryEvaluationConfiguration

    public init(configuration: CADGeometryEvaluationConfiguration) {
        self.configuration = configuration
    }

    public func evaluate(
        _ document: ValidatedCADDocument,
        reusing previous: EvaluatedDocument?,
        admitting limits: TessellationLimits
    ) throws -> EvaluatedDocument {
        // The limits are per-request, so the kernel evaluator is built per call.
        // It is a value type over value types, and injecting no extractor keeps
        // `supportsIncrementalEvaluation` true, so building it here neither
        // costs a traversal nor forfeits incremental reuse.
        let evaluator = DocumentEvaluator(
            tolerance: configuration.tolerance,
            tessellationOptions: configuration.tessellationOptions,
            tessellationLimits: limits,
            artifactPolicy: .materialized
        )
        return try evaluator.evaluate(document, reusing: previous)
    }
}
