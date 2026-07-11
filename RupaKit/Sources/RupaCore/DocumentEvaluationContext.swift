import SwiftCAD
import RupaCoreTypes

public struct DocumentEvaluationContext: Sendable {
    public let generation: DocumentGeneration
    public let modelingSettings: DocumentModelingSettings
    public let evaluatedDocument: EvaluatedDocument
    public let validatedDocument: ValidatedDesignDocument
    private let sourceIdentity: LiveDocumentEvaluationIdentity

    init(
        generation: DocumentGeneration,
        modelingSettings: DocumentModelingSettings,
        evaluatedDocument: EvaluatedDocument,
        validatedDocument: ValidatedDesignDocument
    ) {
        self.generation = generation
        self.modelingSettings = modelingSettings
        self.evaluatedDocument = evaluatedDocument
        self.validatedDocument = validatedDocument
        sourceIdentity = LiveDocumentEvaluationIdentity(document: evaluatedDocument.document)
    }

    init(cache: EvaluatedDocumentCache) {
        self.init(
            generation: cache.generation,
            modelingSettings: cache.modelingSettings,
            evaluatedDocument: cache.evaluatedDocument,
            validatedDocument: cache.validatedDocument
        )
    }

    public var cache: EvaluatedDocumentCache {
        EvaluatedDocumentCache(
            generation: generation,
            modelingSettings: modelingSettings,
            evaluatedDocument: evaluatedDocument,
            validatedDocument: validatedDocument
        )
    }

    public func matches(
        document: DesignDocument,
        generation expectedGeneration: DocumentGeneration?
    ) -> Bool {
        guard let expectedGeneration,
              generation == expectedGeneration,
              modelingSettings == document.modelingSettings else {
            return false
        }
        return sourceIdentity.matches(document.cadDocument)
    }
}
