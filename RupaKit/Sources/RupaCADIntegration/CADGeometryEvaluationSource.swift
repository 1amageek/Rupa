import SwiftCAD

/// Owns the immutable CAD input and evaluation capability for one external source.
public struct CADGeometryEvaluationSource: Sendable {
    public let document: CADDocument
    public let evaluator: any CADDocumentEvaluating
    /// The caller's validation of `document`, when it holds one: evaluation reads it, and the
    /// source fingerprint it carries, instead of validating and hashing the document again.
    public let validatedDocument: ValidatedCADDocument?

    public init(
        document: CADDocument,
        evaluator: any CADDocumentEvaluating
    ) {
        self.document = document
        self.evaluator = evaluator
        validatedDocument = nil
    }

    public init(
        validatedDocument: ValidatedCADDocument,
        evaluator: any CADDocumentEvaluating
    ) {
        document = validatedDocument.document
        self.evaluator = evaluator
        self.validatedDocument = validatedDocument
    }

    public var sourceID: String {
        document.id.description
    }
}
