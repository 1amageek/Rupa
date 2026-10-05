import SwiftCAD

public protocol DrawingOccurrencePlacementResolving: Sendable {
    func placements(document: DesignDocument, evaluated: EvaluatedDocument, savedView: SavedView,
                    maximumOccurrences: Int, maximumPlacements: Int) throws -> [DrawingOccurrenceBodyPlacement]
}
