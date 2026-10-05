import SwiftCAD

/// Original shaped glyph provenance and whole directed Bezier contour sources.
public struct DrawingGlyphContours: Sendable {
    public let outline: DrawingGlyphOutline
    public let contours: [OriginalPlanarContour]
}
