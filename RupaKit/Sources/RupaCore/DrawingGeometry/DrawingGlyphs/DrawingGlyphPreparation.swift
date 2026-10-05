import SwiftCAD

/// One caller-live original contact allowance bound to the complete drawing accountant.
public struct DrawingGlyphPreparation: Sendable {
    public let paperTolerance: ModelingTolerance
    private let accountingOwner: DrawingExchangeUsage
    private var allowance: OriginalCurveContactAllowance

    public init(paperTolerance: ModelingTolerance, maximumSubdivisionCells: Int,
        maximumWork: Int, usage: inout DrawingExchangeUsage) throws {
        try usage.check(); try paperTolerance.validate()
        let admission = OriginalCurveContactAdmission(consumeWork: usage.preparationWorkCallback,
            consumeStorage: usage.preparationStorageCallback)
        allowance = try OriginalCurveContactAllowance(
            maximumSubdivisionDepth: usage.maximumCurveSubdivisionDepth,
            maximumSubdivisionCells: maximumSubdivisionCells, maximumWork: maximumWork,
            tolerance: paperTolerance, admission: admission,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth,
            remainingSourceDepth: min(32, usage.maximumNesting))
        self.paperTolerance = paperTolerance
        accountingOwner = usage
    }

    mutating func boundaries(_ glyphs: [DrawingGlyphContours], usage: inout DrawingExchangeUsage,
        resolver: any DrawingGlyphBoundaryResolving) throws -> [DrawingResolvedGlyphBoundary] {
        guard accountingOwner.sharesAccountingOwner(with: usage) else {
            throw EditorError(code: .evaluationFailed,
                message: "Original glyph preparation belongs to a different drawing accountant.")
        }
        return try resolver.boundaries(glyphs, paperTolerance: paperTolerance,
            allowance: &allowance, usage: &usage)
    }
}
