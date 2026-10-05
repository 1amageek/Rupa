import RupaCore
import SwiftCAD

/// Complete caller policy for one original page preparation and format publication.
public struct DrawingPageAutomationRequest: Codable, Equatable, Sendable {
    public let query: DrawingProjectionQuery
    public let options: DrawingPageAutomationOptions
    public let format: ExchangeFileFormat
    public let outputUnit: LengthUnit
    public let resources: ExchangeResourceLimits
    public let maximumSourceUses: Int
    public let maximumOccurrences: Int
    public let maximumAnnotations: Int
    public let paperTolerance: ModelingTolerance
    public let maximumGlyphSubdivisionCells: Int
    public let maximumGlyphWork: Int
    public let sections: DrawingPageSectionPolicy?
    public let silhouettes: DrawingSilhouettePolicy?

    public init(query: DrawingProjectionQuery, options: DrawingPageAutomationOptions,
        format: ExchangeFileFormat, outputUnit: LengthUnit, resources: ExchangeResourceLimits,
        maximumSourceUses: Int, maximumOccurrences: Int, maximumAnnotations: Int,
        paperTolerance: ModelingTolerance, maximumGlyphSubdivisionCells: Int, maximumGlyphWork: Int,
        sections: DrawingPageSectionPolicy?, silhouettes: DrawingSilhouettePolicy? = nil) {
        self.query = query; self.options = options; self.format = format; self.outputUnit = outputUnit
        self.resources = resources; self.maximumSourceUses = maximumSourceUses
        self.maximumOccurrences = maximumOccurrences; self.maximumAnnotations = maximumAnnotations
        self.paperTolerance = paperTolerance; self.maximumGlyphSubdivisionCells = maximumGlyphSubdivisionCells
        self.maximumGlyphWork = maximumGlyphWork; self.sections = sections; self.silhouettes = silhouettes
    }
    func validate() throws {
        try resources.validate(); try paperTolerance.validate(); try sections?.validate(); try silhouettes?.validate()
        guard [.dxf, .svg, .pdf].contains(format), maximumSourceUses > 0,
              maximumOccurrences > 0, maximumAnnotations > 0,
              maximumGlyphSubdivisionCells > 0, maximumGlyphWork > 0,
              options.dimensionLayouts.count <= maximumAnnotations else {
            throw EditorError(code: .commandInvalid, message: "Original page format or preparation policy is invalid.")
        }
    }
}
