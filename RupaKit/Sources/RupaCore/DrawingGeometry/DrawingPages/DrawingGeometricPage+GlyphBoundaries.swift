import SwiftCAD

extension DrawingGeometricPage {
    public func resolvingGlyphBoundaries(document: DesignDocument, evaluated: EvaluatedDocument,
        preparation: inout DrawingGlyphPreparation, usage: inout DrawingExchangeUsage,
        resolver: any DrawingGlyphBoundaryResolving = DefaultDrawingGlyphBoundaryResolver()) throws -> DrawingGeometricPage {
        try usage.check(); try validateCurrent(document: document, evaluated: evaluated)
        let boundaries = try preparation.boundaries(originalGlyphContours, usage: &usage, resolver: resolver)
        let resolved = DrawingExchangePage(width: page.width, height: page.height,
            paths: page.paths, glyphs: page.glyphs, styles: page.styles,
            maximumGlyphDeviation: page.maximumGlyphDeviation, regions: page.regions,
            resolvedGlyphBoundaries: boundaries)
        return DrawingGeometricPage(original: original, annotations: annotations, page: resolved,
            sections: sections, originalGlyphContours: originalGlyphContours, dimensionLayouts: dimensionLayouts, silhouettes: silhouettes, radialMeasurements: radialMeasurements)
    }
}
