import SwiftCAD

/// Retained original geometric publication, before hidden-line and page composition.
public struct DrawingOccurrenceProjection: Sendable {
    public let savedView: SavedView
    public let original: BRepDrawingProjection
    public let uses: [DrawingOccurrenceProjectedUse]
    public let exchangeProjection: BRepDrawingPlacedProjection
    private let sourceDocument: DesignDocument

    init(document: DesignDocument, savedView: SavedView, original: BRepDrawingProjection,
         uses: [DrawingOccurrenceProjectedUse], exchangeProjection: BRepDrawingPlacedProjection) {
        sourceDocument = document
        self.savedView = savedView
        self.original = original
        self.uses = uses
        self.exchangeProjection = exchangeProjection
    }

    public func validateCurrent(document: DesignDocument, evaluated: EvaluatedDocument) throws {
        try Task.checkCancellation()
        guard document == sourceDocument else {
            throw EditorError(code: .referenceUnresolved,
                message: "Placed drawing belongs to a different original document or scene placement.")
        }
        try original.validateCurrent(evaluated)
    }
}
