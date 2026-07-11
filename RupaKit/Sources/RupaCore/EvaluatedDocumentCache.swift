import SwiftCAD
import RupaCoreTypes

public struct EvaluatedDocumentCache: Sendable {
    public var generation: DocumentGeneration
    public var modelingSettings: DocumentModelingSettings
    public var evaluatedDocument: EvaluatedDocument
    public var validatedDocument: ValidatedDesignDocument
    let sourceIdentity: LiveDocumentEvaluationIdentity

    public init(
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

    public func matches(
        document: DesignDocument,
        generation: DocumentGeneration
    ) -> Bool {
        guard self.generation == generation,
              modelingSettings == document.modelingSettings else {
            return false
        }
        return sourceIdentity.matches(document.cadDocument)
    }
}
