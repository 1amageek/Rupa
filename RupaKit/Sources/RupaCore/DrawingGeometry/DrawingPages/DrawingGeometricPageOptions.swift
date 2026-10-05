import SwiftCAD

/// Explicit authored paper law; no fit, font or scale is inferred.
public struct DrawingGeometricPageOptions: Sendable {
    public let page: DrawingProjectionPage
    public let pointsPerMeter: Double
    public let translation: Point2D
    public let maximumCurveDeviation: Double
    public let maximumGlyphDeviation: Double
    public let font: DrawingGlyphFont
    public let fontSize: Double
    public let labelBaselineOffset: Point2D
    public let styles: DrawingExchangeStyles
    public let dimensionLayouts: [DrawingDimensionLayout]
    public let paperTolerance: ModelingTolerance?

    public init(page: DrawingProjectionPage, pointsPerMeter: Double, translation: Point2D,
                maximumCurveDeviation: Double, maximumGlyphDeviation: Double,
                font: DrawingGlyphFont, fontSize: Double, labelBaselineOffset: Point2D,
                styles: DrawingExchangeStyles, dimensionLayouts: [DrawingDimensionLayout] = [],
                paperTolerance: ModelingTolerance? = nil) throws {
        guard page.width.isFinite, page.width > 0, page.height.isFinite, page.height > 0,
              pointsPerMeter.isFinite, pointsPerMeter > 0,
              translation.x.isFinite, translation.y.isFinite,
              maximumCurveDeviation.isFinite, maximumCurveDeviation > 0,
              maximumGlyphDeviation.isFinite, maximumGlyphDeviation > 0,
              fontSize.isFinite, fontSize > 0,
              labelBaselineOffset.x.isFinite, labelBaselineOffset.y.isFinite else {
            throw EditorError(code: .commandInvalid, message: "Original drawing paper law is invalid.")
        }
        try styles.validate()
        try paperTolerance?.validate()
        self.page = page; self.pointsPerMeter = pointsPerMeter; self.translation = translation
        self.maximumCurveDeviation = maximumCurveDeviation; self.maximumGlyphDeviation = maximumGlyphDeviation
        self.font = font; self.fontSize = fontSize; self.labelBaselineOffset = labelBaselineOffset
        self.styles = styles; self.dimensionLayouts = dimensionLayouts; self.paperTolerance = paperTolerance
    }
    public init(page: DrawingProjectionPage, pointsPerMeter: Double, translation: Point2D,
                maximumCurveDeviation: Double, maximumGlyphDeviation: Double,
                font: DrawingGlyphFont, fontSize: Double, labelBaselineOffset: Point2D,
                style: DrawingProjectionExportStyle, material: DrawingFillStyle,
                dimensionLayouts: [DrawingDimensionLayout] = [], paperTolerance: ModelingTolerance? = nil) throws {
        func stroke(_ value: DrawingProjectionLayerStyle) -> DrawingStrokeStyle {
            DrawingStrokeStyle(red: value.color.red, green: value.color.green, blue: value.color.blue,
                width: value.strokeWidth, dashPattern: value.dashPattern)
        }
        let styles = DrawingExchangeStyles(geometry: stroke(style.unclassified), visible: stroke(style.visible),
            hidden: stroke(style.hidden), partiallyHidden: stroke(style.partiallyHidden),
            sectionContour: stroke(style.sectionContour), sectionHatch: stroke(style.sectionHatch),
            annotation: stroke(style.annotation), material: material)
        try self.init(page: page, pointsPerMeter: pointsPerMeter, translation: translation,
            maximumCurveDeviation: maximumCurveDeviation, maximumGlyphDeviation: maximumGlyphDeviation,
            font: font, fontSize: fontSize, labelBaselineOffset: labelBaselineOffset, styles: styles, dimensionLayouts: dimensionLayouts, paperTolerance: paperTolerance)
    }

}
