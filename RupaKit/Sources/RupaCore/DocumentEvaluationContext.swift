import SwiftCAD
import RupaCoreTypes

public struct DocumentEvaluationContext: Sendable {
    public let generation: DocumentGeneration
    public let sourceFingerprint: CADDocumentSourceFingerprint
    public let modelingSettings: DocumentModelingSettings
    public let evaluatedDocument: EvaluatedDocument

    init(
        generation: DocumentGeneration,
        sourceFingerprint: CADDocumentSourceFingerprint,
        modelingSettings: DocumentModelingSettings,
        evaluatedDocument: EvaluatedDocument
    ) {
        self.generation = generation
        self.sourceFingerprint = sourceFingerprint
        self.modelingSettings = modelingSettings
        self.evaluatedDocument = evaluatedDocument
    }

    init(cache: EvaluatedDocumentCache) {
        self.init(
            generation: cache.generation,
            sourceFingerprint: cache.sourceFingerprint,
            modelingSettings: cache.modelingSettings,
            evaluatedDocument: cache.evaluatedDocument
        )
    }

    public var cache: EvaluatedDocumentCache {
        EvaluatedDocumentCache(
            generation: generation,
            sourceFingerprint: sourceFingerprint,
            modelingSettings: modelingSettings,
            evaluatedDocument: evaluatedDocument
        )
    }

    public func matches(
        document: DesignDocument,
        generation expectedGeneration: DocumentGeneration?
    ) throws -> Bool {
        guard let expectedGeneration,
              generation == expectedGeneration,
              modelingSettings == document.modelingSettings else {
            return false
        }
        let currentFingerprint = try document.cadDocument.sourceFingerprint(
            tolerance: document.modelingSettings.tolerance
        )
        return currentFingerprint == sourceFingerprint
    }
}
