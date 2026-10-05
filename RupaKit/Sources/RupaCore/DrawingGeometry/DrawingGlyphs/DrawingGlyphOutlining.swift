import SwiftCAD

public protocol DrawingGlyphOutlining: Sendable {
    func outlines(text: String, identity: String, font: DrawingGlyphFont, fontSize: Double,
                  baseline: Point2D, usage: inout DrawingExchangeUsage) throws -> [DrawingGlyphOutline]
}
