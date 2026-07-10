import SwiftCAD
import RupaCoreTypes

public struct EvaluatedDocumentCache: Sendable {
    public var generation: DocumentGeneration
    public var sourceFingerprint: CADDocumentSourceFingerprint
    public var modelingSettings: DocumentModelingSettings
    public var evaluatedDocument: EvaluatedDocument

    public init?(
        generation: DocumentGeneration,
        modelingSettings: DocumentModelingSettings,
        evaluatedDocument: EvaluatedDocument
    ) {
        guard let sourceFingerprint = evaluatedDocument.caches.brep?.sourceFingerprint else {
            return nil
        }
        self.generation = generation
        self.sourceFingerprint = sourceFingerprint
        self.modelingSettings = modelingSettings
        self.evaluatedDocument = evaluatedDocument
    }

    public init(
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

    public func matches(
        document: DesignDocument,
        generation: DocumentGeneration
    ) throws -> Bool {
        guard self.generation == generation,
              modelingSettings == document.modelingSettings else {
            return false
        }
        let currentFingerprint = try document.cadDocument.sourceFingerprint(
            tolerance: document.modelingSettings.tolerance
        )
        return currentFingerprint == sourceFingerprint
    }
}
