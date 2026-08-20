import SwiftCAD

/// Owns the immutable CAD input and evaluation capability for one external source.
public struct CADGeometryEvaluationSource: Sendable {
    public let document: CADDocument
    public let evaluator: any CADDocumentEvaluating

    public init(
        document: CADDocument,
        evaluator: any CADDocumentEvaluating
    ) {
        self.document = document
        self.evaluator = evaluator
    }

    public var sourceID: String {
        document.id.description
    }
}
