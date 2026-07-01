import SwiftCAD
import RupaCoreTypes

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
        tolerance: ModelingTolerance? = nil
    ) throws -> Bool {
        guard let expectedGeneration,
              generation == expectedGeneration else {
            return false
        }
        let resolvedTolerance = tolerance ?? .workspaceScaleAware(for: document)
        let currentFingerprint = try document.cadDocument.sourceFingerprint(tolerance: resolvedTolerance)
        return currentFingerprint == sourceFingerprint
    }
}
