import Foundation
import RupaCore
import SwiftCAD

/// Native public command composition of the existing original page and format producers.
public struct DefaultDrawingPageAutomationProducer: DrawingPageAutomationProducing {
    private let drawing: DrawingProjectionService
    public init(drawing: DrawingProjectionService = DrawingProjectionService()) { self.drawing = drawing }

    public func generate(_ request: DrawingPageAutomationRequest,
        in session: EditorSession) throws -> DrawingPageAutomationResult {
        try request.validate()
        var usage = try DrawingExchangeUsage(limits: request.resources, format: request.format)
        let page = try prepare(request, in: session, usage: &usage)
        let sink = DrawingPageByteSink(consumeBytes: usage.preparationStorageCallback)
        try OfficialFormatExchange().write(page.page, as: request.format,
            outputUnit: request.outputUnit, usage: &usage, to: sink)
        try usage.check()
        return DrawingPageAutomationResult(page: page, generation: session.generation,
            format: request.format, output: .bytes(sink.bytes), usage: usage)
    }

    public func export(_ request: DrawingPageAutomationRequest, to url: URL,
        in session: EditorSession) throws -> DrawingPageAutomationResult {
        guard url.isFileURL else { throw invalid("Original page export requires an explicit file URL.") }
        try request.validate()
        var usage = try DrawingExchangeUsage(limits: request.resources, format: request.format)
        let page = try prepare(request, in: session, usage: &usage)
        try OfficialFormatExchange().export(page.page, as: request.format,
            outputUnit: request.outputUnit, usage: &usage, to: url)
        return DrawingPageAutomationResult(page: page, generation: session.generation,
            format: request.format, output: .file(url), usage: usage)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This production command consumes actual
    // original page/section/hatch/glyph algorithms. Full selected SSI/UV classifier
    // accounting, angular source endpoints, visibility and independent endpoint
    // algebra/localization admission must close before all-domain D1/D3/D4 completion.
    private func prepare(_ request: DrawingPageAutomationRequest, in session: EditorSession,
        usage: inout DrawingExchangeUsage) throws -> DrawingGeometricPage {
        let document = session.document
        let options = try request.options.resolved(paperTolerance: request.paperTolerance, usage: &usage)
        var sections: DrawingOccurrenceSections?
        var contributions: [DrawingSectionPageContribution] = []
        if let policy = request.sections {
            let frame = try drawing.originalPageProjectionFrame(document: document, query: request.query)
            let original = try drawing.generateSelectedGeometricSections(document: document,
                query: request.query, projectionFrame: frame, maximumOccurrences: request.maximumOccurrences,
                maximumCuttingSupports: policy.maximumCuttingSupports, maximumSections: policy.maximumSections,
                maximumSourceFaces: policy.maximumSourceFaces, maximumComponents: policy.maximumComponents,
                maximumSourceEntities: policy.maximumSourceEntities, usage: &usage,
                objectRegistry: session.objectRegistry, currentEvaluation: session.currentEvaluation,
                currentGeneration: session.generation)
            sections = original
            let bytes = original.values.count.multipliedReportingOverflow(by: MemoryLayout<DrawingSectionPageContribution>.stride)
            guard !bytes.overflow else { throw invalid("Section page contribution capacity overflowed.") }
            try usage.charge(bytes: bytes.partialValue)
            contributions.reserveCapacity(original.values.count)
            for (index, value) in original.values.enumerated() {
                try usage.check(); try usage.charge(work: 1)
                var segments: [BRepDrawingHatchSegment] = []
                if let hatch = policy.hatch {
                    guard usage.consumedWork < usage.maximumWork, usage.consumedBytes < usage.maximumBytes else {
                        throw invalid("Original hatch preparation exhausted the page allowance.")
                    }
                    let receipt = try drawing.generateOriginalGeometricHatch(document: document,
                        section: value.original, spacing: hatch.spacing, maximumRows: hatch.maximumRows,
                        maximumBoundaryCurves: hatch.maximumBoundaryCurves, maximumEventsPerRow: hatch.maximumEventsPerRow,
                        maximumSegments: hatch.maximumSegments,
                        maximumPreparationWork: usage.maximumWork - usage.consumedWork,
                        maximumPreparationBytes: usage.maximumBytes - usage.consumedBytes,
                        maximumSourceDepth: min(16, usage.maximumNesting),
                        maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
                        maximumAlgebraicDepth: usage.maximumAlgebraicDepth, objectRegistry: session.objectRegistry,
                        currentEvaluation: session.currentEvaluation, currentGeneration: session.generation)
                    try usage.charge(work: receipt.consumedPreparationWork, bytes: receipt.retainedPreparationBytes)
                    segments = receipt.segments
                }
                contributions.append(DrawingSectionPageContribution(sectionIndex: index,
                    regions: [], hatchSegments: segments))
            }
        }
        var glyphs = try DrawingGlyphPreparation(paperTolerance: request.paperTolerance,
            maximumSubdivisionCells: request.maximumGlyphSubdivisionCells,
            maximumWork: request.maximumGlyphWork, usage: &usage)
        // FIXME(INCOMPLETE_IMPLEMENTATION): The requested contour route now emits
        // source-bound exact spans. Complete point-event provenance and certified
        // foreground visibility must also close before all-domain drawing completion.
        if let policy = request.silhouettes {
            var contours = try DrawingSilhouettePreparation(policy: policy, usage: &usage)
            return try drawing.generateGeometricPage(document: document, query: request.query,
                maximumSourceUses: request.maximumSourceUses, maximumOccurrences: request.maximumOccurrences,
                maximumAnnotations: request.maximumAnnotations, sections: sections, sectionContributions: contributions,
                options: options, silhouettePreparation: &contours, glyphPreparation: &glyphs,
                usage: &usage, objectRegistry: session.objectRegistry,
                currentEvaluation: session.currentEvaluation, currentGeneration: session.generation)
        }
        return try drawing.generateGeometricPage(document: document, query: request.query,
            maximumSourceUses: request.maximumSourceUses, maximumOccurrences: request.maximumOccurrences,
            maximumAnnotations: request.maximumAnnotations, sections: sections, sectionContributions: contributions,
            options: options, glyphPreparation: &glyphs, usage: &usage, objectRegistry: session.objectRegistry,
            currentEvaluation: session.currentEvaluation, currentGeneration: session.generation)
    }
    private func invalid(_ message: String) -> EditorError { EditorError(code: .commandInvalid, message: message) }
}
