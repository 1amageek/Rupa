import SwiftCAD

public struct DefaultDrawingGlyphBoundaryResolver: DrawingGlyphBoundaryResolving {
    private let contacts: any OriginalPlanarContourContactPreparing
    private let regions: any OriginalPlanarNonzeroBoundaryResolving

    public init(contacts: any OriginalPlanarContourContactPreparing = DefaultOriginalPlanarContourContactPreparer(),
        regions: any OriginalPlanarNonzeroBoundaryResolving = DefaultOriginalPlanarNonzeroBoundaryResolver()) {
        self.contacts = contacts; self.regions = regions
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The actual Native page/DXF route now carries independent
    // caller subdivision/algebra limits and one accountant. Full source-family closure still depends
    // on the lower exact contact/root endpoints; no unsupported original family becomes parity filling.
    public func boundaries(_ glyphs: [DrawingGlyphContours], paperTolerance: ModelingTolerance,
        allowance: inout OriginalCurveContactAllowance, usage: inout DrawingExchangeUsage)
        throws -> [DrawingResolvedGlyphBoundary] {
        try usage.check(); try paperTolerance.validate()
        let bytes = glyphs.count.multipliedReportingOverflow(by: MemoryLayout<DrawingResolvedGlyphBoundary>.stride)
        guard !bytes.overflow else {
            throw EditorError(code: .evaluationFailed, message: "Resolved glyph retention overflowed.")
        }
        try usage.charge(bytes: bytes.partialValue)
        var result: [DrawingResolvedGlyphBoundary] = []; result.reserveCapacity(glyphs.count)
        let work = usage.preparationWorkCallback
        let storage = usage.preparationStorageCallback
        let plane = Plane3D(origin: .origin, normal: .unitZ, uDirection: .unitX)
        for glyph in glyphs {
            try usage.check(); try usage.charge(work: 1)
            guard glyph.original.fillRule == .nonzero, !glyph.original.commands.isEmpty else { continue }
            guard !glyph.contours.isEmpty else {
                throw EditorError(code: .evaluationFailed, message: "Nonempty original glyph has no planar contour source.")
            }
            let prepared = try contacts.prepare(contours: glyph.contours, on: plane,
                allowance: &allowance, tolerance: paperTolerance, consumeWork: work, consumeStorage: storage)
            let boundary = try regions.boundary(from: prepared, allowance: &allowance,
                consumeWork: work, consumeStorage: storage)
            result.append(try DrawingResolvedGlyphBoundary(original: glyph.original, boundary: boundary, usage: &usage))
        }
        return result
    }
}
