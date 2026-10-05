import SwiftCAD

public protocol DrawingGlyphBoundaryResolving: Sendable {
    func boundaries(_ glyphs: [DrawingGlyphContours], paperTolerance: ModelingTolerance,
        allowance: inout OriginalCurveContactAllowance, usage: inout DrawingExchangeUsage)
        throws -> [DrawingResolvedGlyphBoundary]
}
