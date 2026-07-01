import Foundation
import SwiftCAD

public extension DocumentEvaluator {
    static var modelingDefault: DocumentEvaluator {
        DocumentEvaluator()
    }

    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry _: ObjectTypeRegistry = .builtIn
    ) -> DocumentEvaluator {
        DocumentEvaluator(
            tolerance: .workspaceScaleAware(for: document)
        )
    }
}

public extension CADPipeline {
    static var modelingDefault: CADPipeline {
        CADPipeline(evaluator: .modelingDefault)
    }

    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry _: ObjectTypeRegistry = .builtIn
    ) -> CADPipeline {
        let tolerance = ModelingTolerance.workspaceScaleAware(for: document)
        return CADPipeline(
            evaluator: DocumentEvaluator(tolerance: tolerance),
            snapQueryEvaluator: SnapQueryEvaluator(tolerance: tolerance),
            selectionMeasurementEvaluator: SelectionMeasurementEvaluator(tolerance: tolerance),
            selectionDimensionEvaluator: SelectionDimensionEvaluator(tolerance: tolerance)
        )
    }
}
