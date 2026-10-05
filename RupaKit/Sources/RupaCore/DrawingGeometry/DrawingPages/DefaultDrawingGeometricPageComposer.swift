import Foundation
import SwiftCAD

public struct DefaultDrawingGeometricPageComposer: DrawingGeometricPageComposing {
    private let curves: any BRepDrawingCurveLinearizing
    private let glyphs: any DrawingGlyphOutlining
    private let contourBuilder: any DrawingGlyphContourBuilding
    private let dimensions: any DrawingDimensionStrokeProducing

    public init(curves: any BRepDrawingCurveLinearizing = DefaultBRepDrawingCurveLinearizer(),
                glyphs: any DrawingGlyphOutlining = NativeDrawingGlyphOutliner(),
                contourBuilder: any DrawingGlyphContourBuilding = OriginalDrawingGlyphContourBuilder(),
                dimensions: any DrawingDimensionStrokeProducing = DefaultDrawingDimensionStrokeProducer()) {
        self.curves = curves; self.glyphs = glyphs; self.contourBuilder = contourBuilder; self.dimensions = dimensions
    }

    public func compose(_ projection: DrawingOccurrenceProjection,
                        annotations: DrawingGeometricAnnotations,
                        document: DesignDocument, evaluated: EvaluatedDocument,
                        options: DrawingGeometricPageOptions,
                        usage: inout DrawingExchangeUsage) throws -> DrawingGeometricPage {
        try usage.check()
        try projection.validateCurrent(document: document, evaluated: evaluated)
        try annotations.validateCurrent(document: document, evaluated: evaluated)
        guard annotations.savedViewID == projection.savedView.id else {
            throw invalid("Drawing dimensions and geometry use different original saved views.")
        }
        let sourceDeviation = ((options.maximumCurveDeviation / 2).nextDown / options.pointsPerMeter).nextDown
        guard sourceDeviation.isFinite, sourceDeviation > 0 else { throw invalid("Original drawing precision is exhausted.") }
        var paths: [DrawingPagePath] = []
        var outlines: [DrawingGlyphOutline] = []
        var originalGlyphContours: [DrawingGlyphContours] = []
        var glyphIdentity: UInt64 = 0
        var glyphCapacity = 0
        for (ordinal, use) in projection.exchangeProjection.uses.enumerated() {
            try usage.check(); try usage.charge(work: 1)
            let source = try curves.linearize(use.curve, from: use.original.edge.startParameter,
                to: use.original.edge.endParameter, maximumDeviation: sourceDeviation, usage: &usage)
            let bytes = source.samples.count.multipliedReportingOverflow(by: MemoryLayout<Point2D>.stride + MemoryLayout<Double>.stride)
            guard !bytes.overflow else { throw invalid("Paper sample admission overflowed.") }
            try usage.charge(entities: 1, bytes: bytes.partialValue)
            try usage.charge(bytes: MemoryLayout<DrawingPagePath>.stride)
            var points: [Point2D] = []; var parameters: [Double] = []
            points.reserveCapacity(source.samples.count); parameters.reserveCapacity(source.samples.count)
            for sample in source.samples {
                try usage.check(); try usage.charge(work: 1)
                points.append(try map(sample.point, options: options)); parameters.append(sample.parameter)
            }
            let identity = try admittedIdentity(use.placement.identity, suffix: ".use.", ordinal: ordinal, usage: &usage)
            paths.append(DrawingPagePath(points: points, identity: identity, role: .geometry, originalParameters: parameters))
        }
        for index in options.dimensionLayouts.indices {
            let layout = options.dimensionLayouts[index]
            for prior in 0..<index {
                try usage.charge(work: 1)
                guard options.dimensionLayouts[prior].annotationID != layout.annotationID else {
                    throw invalid("Paper dimension layouts duplicate an original annotation identity.")
                }
            }
            guard let annotation = annotations.values.first(where: { $0.id == layout.annotationID }) else {
                throw invalid("Paper dimension layout names no current original annotation.")
            }
            try usage.charge(work: annotations.radialMeasurements.count)
            let radial = annotations.radialMeasurements.first { $0.annotation.id == annotation.id }
            let strokes = try dimensions.paths(annotation: annotation, layout: layout, options: options,
                radialMeasurement: radial, frame: projection.original.frame, usage: &usage)
            let count = paths.count.addingReportingOverflow(strokes.count)
            let bytes = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<DrawingPagePath>.stride)
            guard !count.overflow, !bytes.overflow else { throw invalid("Dimension page stroke storage overflowed.") }
            try usage.charge(bytes: bytes.partialValue)
            paths.reserveCapacity(count.partialValue); paths.append(contentsOf: strokes)
        }
        for annotation in annotations.values {
            try usage.check(); try usage.charge(work: 1)
            guard !annotation.displayText.isEmpty else { throw invalid("Resolved drawing label is empty.") }
            let label = try map(annotation.labelPoint2D, options: options)
            let baseline = Point2D(x: label.x + options.labelBaselineOffset.x, y: label.y + options.labelBaselineOffset.y)
            guard baseline.x.isFinite, baseline.y.isFinite else { throw invalid("Drawing baseline exceeds paper precision.") }
            let runs = try glyphs.outlines(text: annotation.displayText, identity: annotation.id,
                font: options.font, fontSize: options.fontSize, baseline: baseline, usage: &usage)
            let required = outlines.count.addingReportingOverflow(runs.count)
            guard !required.overflow else { throw invalid("Page glyph count overflowed.") }
            if required.partialValue > glyphCapacity {
                let doubled = glyphCapacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { throw invalid("Page glyph capacity overflowed.") }
                let capacity = max(required.partialValue, doubled.partialValue)
                let bytes = capacity.multipliedReportingOverflow(by:
                    MemoryLayout<DrawingGlyphOutline>.stride + MemoryLayout<DrawingGlyphContours>.stride)
                guard !bytes.overflow else { throw invalid("Page glyph retention overflowed.") }
                // Original run records, old page buffers and new contiguous capacity coexist.
                try usage.charge(bytes: bytes.partialValue)
                outlines.reserveCapacity(capacity); originalGlyphContours.reserveCapacity(capacity)
                glyphCapacity = capacity
            }
            outlines.append(contentsOf: runs)
            for run in runs {
                originalGlyphContours.append(try contourBuilder.contours(run, nextIdentity: &glyphIdentity, usage: &usage))
            }
            if let layout = annotation.labelLayout {
                switch (layout.leaderStart2D, layout.leaderEnd2D) {
                case let (start?, end?):
                    try usage.charge(entities: 1, bytes: MemoryLayout<DrawingPagePath>.stride + 2 * MemoryLayout<Point2D>.stride)
                    let identity = try admittedIdentity(annotation.id, suffix: ".leader.", ordinal: 0, usage: &usage)
                    paths.append(DrawingPagePath(points: [try map(start, options: options), try map(end, options: options)],
                        identity: identity, role: .annotation))
                case (nil, nil): break
                default: throw invalid("Original dimension leader has only one endpoint.")
                }
            }
        }
        return DrawingGeometricPage(original: projection, annotations: annotations.values,
            page: DrawingExchangePage(width: options.page.width, height: options.page.height,
                paths: paths, glyphs: outlines, styles: options.styles, maximumGlyphDeviation: options.maximumGlyphDeviation),
            originalGlyphContours: originalGlyphContours, dimensionLayouts: options.dimensionLayouts, radialMeasurements: annotations.radialMeasurements)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Actual placed section/page composition does
    // not replace complete original SSI/visibility or the DXF nonzero glyph union.
    public func compose(_ projection: DrawingOccurrenceProjection,
                        annotations: DrawingGeometricAnnotations, sections: DrawingOccurrenceSections,
                        contributions: [DrawingSectionPageContribution],
                        document: DesignDocument, evaluated: EvaluatedDocument,
                        options: DrawingGeometricPageOptions,
                        usage: inout DrawingExchangeUsage) throws -> DrawingGeometricPage {
        try sections.validateCurrent(document: document, evaluated: evaluated)
        guard sections.savedView == projection.savedView,
              contributions.count == sections.values.count else {
            throw invalid("Section page inputs disagree with the original saved view or occurrence coverage.")
        }
        // Admit all provenance before shaping fonts or retaining paper output.
        for (index, contribution) in contributions.enumerated() {
            try usage.check(); try usage.charge(work: 1)
            guard contribution.sectionIndex == index else { throw invalid("Section contributions are missing, duplicated or reordered.") }
            let section = sections.values[index].original
            for region in contribution.regions { try region.validateCurrent(evaluated, for: section) }
            for segment in contribution.hatchSegments { try segment.validateCurrent(evaluated, for: section) }
        }
        let base = try compose(projection, annotations: annotations, document: document,
            evaluated: evaluated, options: options, usage: &usage)
        let sectionPage = try DrawingSectionPageComposer(curves: curves).compose(base: base.page,
            projection: projection, sections: sections, contributions: contributions,
            evaluated: evaluated, options: options, usage: &usage)
        return DrawingGeometricPage(original: projection, annotations: annotations.values,
            page: sectionPage, sections: sections, originalGlyphContours: base.originalGlyphContours, dimensionLayouts: base.dimensionLayouts, radialMeasurements: base.radialMeasurements)
    }

    private func map(_ point: Point2D, options: DrawingGeometricPageOptions) throws -> Point2D {
        try DrawingPaperMapper(options: options).map(point)
    }

    private func admittedIdentity(_ base: String, suffix: String, ordinal: Int,
                                  usage: inout DrawingExchangeUsage) throws -> String {
        let bytes = base.utf8.count.addingReportingOverflow(suffix.utf8.count + 20)
        guard !bytes.overflow else { throw invalid("Paper identity admission overflowed.") }
        try usage.charge(bytes: bytes.partialValue)
        return base + suffix + String(ordinal)
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .evaluationFailed, message: message)
    }
}
