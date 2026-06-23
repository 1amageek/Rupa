import Foundation
import SwiftCAD

public extension DocumentEvaluator {
    static var modelingDefault: DocumentEvaluator {
        DocumentEvaluator()
    }

    static func modelingDefault(
        for _: DesignDocument,
        objectRegistry _: ObjectTypeRegistry = .builtIn
    ) -> DocumentEvaluator {
        .modelingDefault
    }
}

public extension CADPipeline {
    static var modelingDefault: CADPipeline {
        CADPipeline(evaluator: .modelingDefault)
    }

    static func modelingDefault(
        for _: DesignDocument,
        objectRegistry _: ObjectTypeRegistry = .builtIn
    ) -> CADPipeline {
        .modelingDefault
    }
}
