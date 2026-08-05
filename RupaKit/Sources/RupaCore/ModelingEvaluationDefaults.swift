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
            artifactPolicy: .materialized
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
                artifactPolicy: .materialized
            )
        )
    }
}
