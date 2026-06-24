import SwiftCAD

public struct DocumentEvaluationContext: Sendable {
    public let generation: DocumentGeneration
    public let sourceFingerprint: CADDocumentSourceFingerprint
    public let evaluatedDocument: EvaluatedDocument

    init(
        generation: DocumentGeneration,
        sourceFingerprint: CADDocumentSourceFingerprint,
        evaluatedDocument: EvaluatedDocument
    ) {
        self.generation = generation
        self.sourceFingerprint = sourceFingerprint
        self.evaluatedDocument = evaluatedDocument
    }

    init(cache: EvaluatedDocumentCache) {
        self.init(
            generation: cache.generation,
            sourceFingerprint: cache.sourceFingerprint,
            evaluatedDocument: cache.evaluatedDocument
        )
    }

    public var cache: EvaluatedDocumentCache {
        EvaluatedDocumentCache(
            generation: generation,
            sourceFingerprint: sourceFingerprint,
            evaluatedDocument: evaluatedDocument
        )
    }

    public func matches(
        document: DesignDocument,
        generation expectedGeneration: DocumentGeneration?,
        tolerance: ModelingTolerance = .standard
    ) throws -> Bool {
        guard let expectedGeneration,
              generation == expectedGeneration else {
            return false
        }
        let currentFingerprint = try document.cadDocument.sourceFingerprint(tolerance: tolerance)
        return currentFingerprint == sourceFingerprint
    }
}
