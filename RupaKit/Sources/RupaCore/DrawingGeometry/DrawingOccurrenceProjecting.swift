import SwiftCAD

public protocol DrawingOccurrenceProjecting: Sendable {
    func project(_ original: BRepDrawingProjection, document: DesignDocument,
                 evaluated: EvaluatedDocument, savedView: SavedView,
                 maximumOccurrences: Int, maximumProjectedUses: Int) throws -> DrawingOccurrenceProjection
}
