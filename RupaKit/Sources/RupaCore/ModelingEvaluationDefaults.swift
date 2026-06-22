import Foundation
import SwiftCAD

public extension DocumentEvaluator {
    static var modelingDefault: DocumentEvaluator {
        DocumentEvaluator(profileExtractor: CircleAwareSketchProfileExtractor())
    }

    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> DocumentEvaluator {
        DocumentEvaluator(
            profileExtractor: CircleAwareSketchProfileExtractor(
                circleSegmentCountsByFeatureID: document.profileSegmentCounts(
                    objectRegistry: objectRegistry
                )
            )
        )
    }
}

public extension CADPipeline {
    static var modelingDefault: CADPipeline {
        CADPipeline(evaluator: .modelingDefault)
    }

    static func modelingDefault(
        for document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> CADPipeline {
        CADPipeline(
            evaluator: .modelingDefault(
                for: document,
                objectRegistry: objectRegistry
            )
        )
    }
}
