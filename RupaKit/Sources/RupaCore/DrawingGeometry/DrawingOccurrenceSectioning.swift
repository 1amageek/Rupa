import SwiftCAD

public protocol DrawingOccurrenceSectioning: Sendable {
    func sections(document: DesignDocument, evaluated: EvaluatedDocument, savedView: SavedView,
                  on supports: [BRepDrawingCuttingSupport], projectionFrame: OrthographicProjectionFrame,
                  maximumOccurrences: Int, maximumSections: Int, maximumSourceFaces: Int, maximumComponents: Int,
                  maximumSourceEntities: Int, maximumPreparationWork: Int, maximumPreparationBytes: Int,
                  maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> DrawingOccurrenceSections

    func sections(document: DesignDocument, evaluated: EvaluatedDocument, savedView: SavedView,
                  on frame: OrthographicProjectionFrame, maximumOccurrences: Int, maximumSections: Int,
                  maximumSourceFaces: Int, maximumComponents: Int, maximumSourceEntities: Int,
                  maximumPreparationWork: Int) throws -> DrawingOccurrenceSections
}
