import Foundation
import SwiftCAD

public extension DocumentEvaluator {
    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry _: ObjectTypeRegistry = .builtIn
    ) -> DocumentEvaluator {
        DocumentEvaluator(
            tolerance: document.modelingSettings.tolerance,
            tessellationOptions: document.modelingSettings.tessellationOptions,
            artifactPolicy: .deferred
        )
    }
}

public extension CADPipeline {
    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry _: ObjectTypeRegistry = .builtIn
    ) -> CADPipeline {
        let tolerance = document.modelingSettings.tolerance
        return CADPipeline(
            tolerance: tolerance,
            evaluator: DocumentEvaluator(
                tolerance: tolerance,
                tessellationOptions: document.modelingSettings.tessellationOptions,
                artifactPolicy: .deferred
            ),
            snapQueryEvaluator: SnapQueryEvaluator(tolerance: tolerance),
            selectionMeasurementEvaluator: SelectionMeasurementEvaluator(tolerance: tolerance),
            selectionDimensionEvaluator: SelectionDimensionEvaluator(tolerance: tolerance)
        )
    }
}
