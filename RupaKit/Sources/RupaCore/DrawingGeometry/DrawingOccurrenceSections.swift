import SwiftCAD

/// Complete scene-bound publication of the admitted visible body occurrence sections.
public struct DrawingOccurrenceSections: Sendable {
    public let savedView: SavedView
    public let values: [DrawingOccurrenceSection]
    public let consumedPreparationWork: Int
    public let retainedPreparationEntities: Int
    public let retainedPreparationBytes: Int
    private let sourceDocument: DesignDocument
    private let configuration: DocumentEvaluationConfiguration
    private let originalBRep: BRepModel

    init(document: DesignDocument, evaluated: EvaluatedDocument, savedView: SavedView, values: [DrawingOccurrenceSection],
         consumedPreparationWork: Int, retainedPreparationEntities: Int, retainedPreparationBytes: Int = 0) {
        sourceDocument = document; configuration = evaluated.configuration; originalBRep = evaluated.brep
        self.savedView = savedView; self.values = values
        self.consumedPreparationWork = consumedPreparationWork
        self.retainedPreparationEntities = retainedPreparationEntities
        self.retainedPreparationBytes = retainedPreparationBytes
    }

    public func validateCurrent(document: DesignDocument, evaluated: EvaluatedDocument) throws {
        try Task.checkCancellation()
        guard document == sourceDocument, evaluated.document == document.cadDocument,
              evaluated.configuration == configuration, evaluated.brep == originalBRep else {
            throw EditorError(code: .referenceUnresolved, message: "Placed sections belong to a different current scene or source.")
        }
        for value in values {
            try value.original.validateCurrent(evaluated)
            guard value.original.placement == value.occurrence.original else {
                throw EditorError(code: .referenceUnresolved, message: "Placed section lost its original occurrence authority.")
            }
        }
    }
}
