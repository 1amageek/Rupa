import RupaCore
import SwiftCAD

/// Explicit Native wire configuration for the existing original paper composer.
public struct DrawingPageAutomationOptions: Codable, Equatable, Sendable {
    public let page: DrawingProjectionPage
    public let pointsPerMeter: Double
    public let translation: Point2D
    public let maximumCurveDeviation: Double
    public let maximumGlyphDeviation: Double
    public let fontPostScriptName: String
    public let allowedFallbackPostScriptNames: [String]
    public let fontSize: Double
    public let labelBaselineOffset: Point2D
    public let style: DrawingProjectionExportStyle
    public let material: DrawingProjectionColor
    public let dimensionLayouts: [DrawingDimensionLayout]

    public init(page: DrawingProjectionPage, pointsPerMeter: Double, translation: Point2D,
        maximumCurveDeviation: Double, maximumGlyphDeviation: Double,
        fontPostScriptName: String, allowedFallbackPostScriptNames: [String],
        fontSize: Double, labelBaselineOffset: Point2D, style: DrawingProjectionExportStyle,
        material: DrawingProjectionColor, dimensionLayouts: [DrawingDimensionLayout]) {
        self.page = page; self.pointsPerMeter = pointsPerMeter; self.translation = translation
        self.maximumCurveDeviation = maximumCurveDeviation; self.maximumGlyphDeviation = maximumGlyphDeviation
        self.fontPostScriptName = fontPostScriptName; self.allowedFallbackPostScriptNames = allowedFallbackPostScriptNames
        self.fontSize = fontSize; self.labelBaselineOffset = labelBaselineOffset
        self.style = style; self.material = material; self.dimensionLayouts = dimensionLayouts
    }

    func resolved(paperTolerance: ModelingTolerance, usage: inout DrawingExchangeUsage) throws -> DrawingGeometricPageOptions {
        try usage.check()
        try usage.charge(work: 1, bytes: fontPostScriptName.utf8.count)
        for name in allowedFallbackPostScriptNames {
            try usage.charge(work: 1, bytes: name.utf8.count)
        }
        let bytes = dimensionLayouts.count.multipliedReportingOverflow(by: MemoryLayout<DrawingDimensionLayout>.stride)
        guard !bytes.overflow else { throw invalid("Paper dimension configuration storage overflowed.") }
        try usage.charge(bytes: bytes.partialValue)
        var layouts: [DrawingDimensionLayout] = []; layouts.reserveCapacity(dimensionLayouts.count)
        for value in dimensionLayouts {
            try usage.check(); try usage.charge(work: 1, bytes: value.annotationID.utf8.count)
            let style = value.style
            let validated = try DrawingDimensionStyle(extensionGap: style.extensionGap,
                extensionOvershoot: style.extensionOvershoot, arrowLength: style.arrowLength,
                arrowWidth: style.arrowWidth, arrowKind: style.arrowKind)
            layouts.append(try DrawingDimensionLayout(annotationID: value.annotationID,
                geometry: value.geometry, style: validated))
        }
        return try DrawingGeometricPageOptions(page: page, pointsPerMeter: pointsPerMeter,
            translation: translation, maximumCurveDeviation: maximumCurveDeviation,
            maximumGlyphDeviation: maximumGlyphDeviation,
            font: DrawingGlyphFont(postScriptName: fontPostScriptName,
                allowedFallbackPostScriptNames: allowedFallbackPostScriptNames),
            fontSize: fontSize, labelBaselineOffset: labelBaselineOffset, style: style,
            material: DrawingFillStyle(red: material.red, green: material.green, blue: material.blue),
            dimensionLayouts: layouts, paperTolerance: paperTolerance)
    }
    private func invalid(_ message: String) -> EditorError { EditorError(code: .commandInvalid, message: message) }
}
