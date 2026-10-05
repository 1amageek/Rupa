import SwiftCAD

extension DrawingGeometricPage {
    public func addingSilhouettes(document: DesignDocument, evaluated: EvaluatedDocument,
        options: DrawingGeometricPageOptions, preparation: inout DrawingSilhouettePreparation,
        usage: inout DrawingExchangeUsage) throws -> DrawingGeometricPage {
        try validateCurrent(document: document, evaluated: evaluated)
        let contours = try preparation.silhouettes(original, document: document, evaluated: evaluated, usage: &usage)
        let additions = try preparation.paths(contours, document: document, evaluated: evaluated,
            options: options, usage: &usage)
        let count = page.paths.count.addingReportingOverflow(additions.count)
        let bytes = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<DrawingPagePath>.stride)
        guard !count.overflow, !bytes.overflow else {
            throw EditorError(code: .evaluationFailed, message: "Whole contour page storage overflowed.")
        }
        try usage.charge(bytes: bytes.partialValue)
        var paths: [DrawingPagePath] = []; paths.reserveCapacity(count.partialValue)
        paths.append(contentsOf: page.paths); paths.append(contentsOf: additions)
        let result = DrawingExchangePage(width: page.width, height: page.height, paths: paths,
            glyphs: page.glyphs, styles: page.styles, maximumGlyphDeviation: page.maximumGlyphDeviation,
            regions: page.regions, resolvedGlyphBoundaries: page.resolvedGlyphBoundaries)
        return DrawingGeometricPage(original: original, annotations: annotations, page: result,
            sections: sections, originalGlyphContours: originalGlyphContours,
            dimensionLayouts: dimensionLayouts, silhouettes: contours, radialMeasurements: radialMeasurements)
    }
}
