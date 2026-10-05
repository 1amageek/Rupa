import SwiftCAD

/// Complete placed contour receipt retaining exact trim and contact source authority.
public struct DrawingOccurrenceSilhouettes: Sendable {
    public let projection: DrawingOccurrenceProjection
    public let values: [BRepDrawingSilhouettes]

    init(projection: DrawingOccurrenceProjection, values: [BRepDrawingSilhouettes]) {
        self.projection = projection; self.values = values
    }
    public func validateCurrent(document: DesignDocument, evaluated: EvaluatedDocument) throws {
        try projection.validateCurrent(document: document, evaluated: evaluated)
        guard values.count == projection.exchangeProjection.placements.count else {
            throw EditorError(code: .referenceUnresolved, message: "Silhouette occurrence coverage changed.")
        }
        for index in values.indices {
            try Task.checkCancellation()
            try values[index].validateCurrent(evaluated)
            guard values[index].placement == projection.exchangeProjection.placements[index] else {
                throw EditorError(code: .referenceUnresolved, message: "Silhouette original placement changed.")
            }
        }
    }
}
