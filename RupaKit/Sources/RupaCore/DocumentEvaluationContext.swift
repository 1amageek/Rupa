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
}
