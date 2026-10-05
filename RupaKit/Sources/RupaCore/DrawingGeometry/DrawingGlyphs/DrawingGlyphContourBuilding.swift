import SwiftCAD

public protocol DrawingGlyphContourBuilding: Sendable {
    func contours(_ outline: DrawingGlyphOutline, nextIdentity: inout UInt64,
                  usage: inout DrawingExchangeUsage) throws -> DrawingGlyphContours
}
