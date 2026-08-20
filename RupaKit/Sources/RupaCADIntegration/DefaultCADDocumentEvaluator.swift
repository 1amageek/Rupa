import SwiftCAD

/// The production Swift-CAD evaluator used by the universal CAD provider.
public struct DefaultCADDocumentEvaluator: CADDocumentEvaluating {
    public let configuration: CADGeometryEvaluationConfiguration
    private let evaluator: DocumentEvaluator

    public init(configuration: CADGeometryEvaluationConfiguration) {
        self.configuration = configuration
        evaluator = DocumentEvaluator(
            tolerance: configuration.tolerance,
            tessellationOptions: configuration.tessellationOptions,
            artifactPolicy: .materialized
        )
    }

    public func evaluate(
        _ document: ValidatedCADDocument,
        reusing previous: EvaluatedDocument?
    ) throws -> EvaluatedDocument {
        try evaluator.evaluate(document, reusing: previous)
    }
}
