import SwiftCAD

public protocol DrawingCuttingSupportResolving: Sendable {
    func supports(document: DesignDocument, savedView: SavedView, maximumOccurrences: Int,
                  maximumSupports: Int, usage: inout DrawingExchangeUsage) throws -> [BRepDrawingCuttingSupport]
}
