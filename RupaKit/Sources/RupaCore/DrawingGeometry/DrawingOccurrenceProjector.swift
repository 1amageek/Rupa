import SwiftCAD
import RupaCoreTypes

/// Projects exact original curve laws through original affine scene occurrences.
public struct DrawingOccurrenceProjector: DrawingOccurrenceProjecting {
    private let curves: any OrthographicCurveProjecting
    private let placements: any DrawingOccurrencePlacementResolving

    public init(curves: any OrthographicCurveProjecting = DefaultOrthographicCurveProjector(),
                placements: any DrawingOccurrencePlacementResolving = DefaultDrawingOccurrencePlacementResolver()) {
        self.curves = curves
        self.placements = placements
    }

    public func project(_ original: BRepDrawingProjection, document: DesignDocument,
                        evaluated: EvaluatedDocument, savedView: SavedView,
                        maximumOccurrences: Int, maximumProjectedUses: Int) throws -> DrawingOccurrenceProjection {
        try Task.checkCancellation()
        try original.validateCurrent(evaluated)
        guard maximumOccurrences > 0, maximumProjectedUses > 0 else {
            throw EditorError(code: .commandInvalid, message: "Placed drawing capacities must be positive.")
        }
        let placementCapacity = maximumOccurrences.multipliedReportingOverflow(by: evaluated.brep.bodies.count)
        guard !placementCapacity.overflow else {
            throw EditorError(code: .commandInvalid, message: "Placed drawing body capacity overflows.")
        }
        let resolved = try placements.placements(document: document, evaluated: evaluated, savedView: savedView,
            maximumOccurrences: maximumOccurrences, maximumPlacements: max(1, placementCapacity.partialValue))
        var contexts: [String: DrawingOccurrenceBodyPlacement] = [:]
        var originalPlacements: [BRepDrawingPlacement] = []
        for placement in resolved {
            contexts[placement.original.identity] = placement
            originalPlacements.append(placement.original)
        }
        let exchangeProjection = try DefaultBRepDrawingPlacer(curves: curves).place(original,
            in: evaluated, placements: originalPlacements,
            maximumPlacements: max(1, placementCapacity.partialValue),
            maximumProjectedUses: maximumProjectedUses)
        var output: [DrawingOccurrenceProjectedUse] = []
        output.reserveCapacity(exchangeProjection.uses.count)
        for use in exchangeProjection.uses {
            try Task.checkCancellation()
            guard let context = contexts[use.placement.identity] else {
                throw EditorError(code: .referenceUnresolved, message: "Placed curve lost its original occurrence identity.")
            }
            output.append(DrawingOccurrenceProjectedUse(occurrenceID: context.occurrenceID,
                sceneNodeID: context.sceneNodeID,
                sourceSceneNodeID: context.sourceSceneNodeID,
                featureID: context.featureID, placement: context.placement,
                original: use.original, curve: use.curve))
        }
        try Task.checkCancellation()
        return DrawingOccurrenceProjection(document: document, savedView: savedView,
            original: original, uses: output, exchangeProjection: exchangeProjection)
    }
}
