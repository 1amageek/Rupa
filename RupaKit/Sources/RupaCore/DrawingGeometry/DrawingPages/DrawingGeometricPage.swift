import SwiftCAD

/// Immutable geometric page retaining the complete original scene/evaluation receipt.
public struct DrawingGeometricPage: Sendable {
    public let original: DrawingOccurrenceProjection
    public let radialMeasurements: [DrawingRadialDimensionMeasurement]
    public let annotations: [DrawingProjectionResult.Annotation]
    public let sections: DrawingOccurrenceSections?
    public let silhouettes: DrawingOccurrenceSilhouettes?
    public let originalGlyphContours: [DrawingGlyphContours]
    public let dimensionLayouts: [DrawingDimensionLayout]
    public let page: DrawingExchangePage

    init(original: DrawingOccurrenceProjection, annotations: [DrawingProjectionResult.Annotation],
         page: DrawingExchangePage, sections: DrawingOccurrenceSections? = nil,
         originalGlyphContours: [DrawingGlyphContours] = [], dimensionLayouts: [DrawingDimensionLayout] = [], silhouettes: DrawingOccurrenceSilhouettes? = nil, radialMeasurements: [DrawingRadialDimensionMeasurement] = []) {
        self.radialMeasurements = radialMeasurements
        self.originalGlyphContours = originalGlyphContours; self.dimensionLayouts = dimensionLayouts
        self.silhouettes = silhouettes
        self.original = original; self.annotations = annotations; self.page = page; self.sections = sections
    }

    public func validateCurrent(document: DesignDocument, evaluated: EvaluatedDocument) throws {
        try original.validateCurrent(document: document, evaluated: evaluated)
        try sections?.validateCurrent(document: document, evaluated: evaluated)
        try silhouettes?.validateCurrent(document: document, evaluated: evaluated)
    }
}
