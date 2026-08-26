import RupaCore
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func workspacePresentationScaleFitUsesPublishedGeometryBoundsInsteadOfCADDocumentBounds() {
    let bounds = MeasurementResult.Bounds(
        minX: 100_000.0,
        minY: 0.0,
        minZ: 200_000.0,
        maxX: 125_000.0,
        maxY: 100.0,
        maxZ: 210_000.0
    )

    let plan = WorkspaceScaleFitService().plan(
        bounds: bounds,
        ruler: .standard(for: .millimeter)
    )

    #expect(plan.action == .applyPreset(.sitePlanning))
    #expect(plan.measurement.bounds == bounds)
    #expect(plan.recommendation?.modelSpanMeters == 25_000.0)
}
