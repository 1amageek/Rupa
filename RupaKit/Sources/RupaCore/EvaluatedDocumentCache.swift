import SwiftCAD
import RupaCoreTypes

public struct EvaluatedDocumentCache: Sendable {
    public var generation: DocumentGeneration
    public var sourceFingerprint: CADDocumentSourceFingerprint
    public var evaluatedDocument: EvaluatedDocument

    public init?(
        generation: DocumentGeneration,
        evaluatedDocument: EvaluatedDocument
    ) {
        guard let sourceFingerprint = evaluatedDocument.caches.brep?.sourceFingerprint else {
            return nil
        }
        self.generation = generation
        self.sourceFingerprint = sourceFingerprint
        self.evaluatedDocument = evaluatedDocument
    }

    public init(
        generation: DocumentGeneration,
        sourceFingerprint: CADDocumentSourceFingerprint,
        evaluatedDocument: EvaluatedDocument
    ) {
        self.generation = generation
        self.sourceFingerprint = sourceFingerprint
        self.evaluatedDocument = evaluatedDocument
    }

    public func matches(
        document: DesignDocument,
        generation: DocumentGeneration,
        tolerance: ModelingTolerance = .standard
    ) throws -> Bool {
        guard self.generation == generation else {
            return false
        }
        let currentFingerprint = try document.cadDocument.sourceFingerprint(tolerance: tolerance)
        return currentFingerprint == sourceFingerprint
    }
}
