import Foundation
import SwiftCAD

public extension DocumentEvaluator {
    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> DocumentEvaluator {
        DocumentEvaluator(
            tolerance: document.modelingSettings.tolerance,
            tessellationOptions: try document.displayTessellationOptions(objectRegistry: objectRegistry),
            artifactPolicy: .materialized
        )
    }
}

public extension CADPipeline {
    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> CADPipeline {
        let tolerance = document.modelingSettings.tolerance
        return CADPipeline(
            tolerance: tolerance,
            evaluator: DocumentEvaluator(
                tolerance: tolerance,
                tessellationOptions: try document.displayTessellationOptions(objectRegistry: objectRegistry),
                artifactPolicy: .materialized
            )
        )
    }
}
