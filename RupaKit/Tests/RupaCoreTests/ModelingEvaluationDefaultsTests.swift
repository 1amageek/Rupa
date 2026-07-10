import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func modelingToleranceRecommendationTracksVisibleSpan() {
    let micro = ModelingTolerance.recommended(
        forVisibleSpanMeters: WorkspaceScalePreset.microFabrication.rulerConfiguration.visibleSpanMeters
    )
    let precision = ModelingTolerance.recommended(
        forVisibleSpanMeters: WorkspaceScalePreset.precisionMechanical.rulerConfiguration.visibleSpanMeters
    )
    let architecture = ModelingTolerance.recommended(
        forVisibleSpanMeters: WorkspaceScalePreset.architecture.rulerConfiguration.visibleSpanMeters
    )
    let site = ModelingTolerance.recommended(
        forVisibleSpanMeters: WorkspaceScalePreset.sitePlanning.rulerConfiguration.visibleSpanMeters
    )

    #expect(approximatelyEqual(micro.distance, 1.0e-8))
    #expect(approximatelyEqual(precision.distance, 1.0e-8))
    #expect(approximatelyEqual(architecture.distance, 2.0e-6))
    #expect(approximatelyEqual(site.distance, 1.0e-4))
    #expect(micro.angle == ModelingTolerance.standard.angle)
    #expect(site.angle == ModelingTolerance.standard.angle)
}

@Test func modelingToleranceRecommendationClampsVisibleSpanExtremes() {
    let smallest = ModelingTolerance.recommended(
        forVisibleSpanMeters: RulerConfiguration.visibleSpanMetersRange.lowerBound
    )
    let largest = ModelingTolerance.recommended(
        forVisibleSpanMeters: RulerConfiguration.visibleSpanMetersRange.upperBound
    )

    #expect(approximatelyEqual(smallest.distance, 1.0e-8))
    #expect(approximatelyEqual(largest.distance, 1.0e-3))
}

@MainActor
@Test func modelingDefaultPipelineEvaluatesSubMicronGeometryAtMicroScale() throws {
    var document = DesignDocument.empty(named: "Micro Geometry")
    document.modelingSettings = DocumentModelingSettings(
        tolerance: ModelingTolerance(distance: 1.0e-8, angle: 1.0e-9),
        tessellationOptions: TessellationOptions(
            linearTolerance: 1.0e-8,
            angularTolerance: 1.0e-3
        )
    )
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Submicron Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .micrometer),
            y: .length(0.0, .micrometer)
        ),
        oppositeCorner: SketchPoint(
            x: .length(0.5, .micrometer),
            y: .length(0.5, .micrometer)
        )
    )
    _ = try document.extrudeProfile(
        name: "Submicron Solid",
        profile: ProfileReference(featureID: profileID),
        distance: .length(0.5, .micrometer),
        direction: .normal
    )

    let evaluated = try CADPipeline.modelingDefault(for: document).evaluate(document.cadDocument)

    #expect(evaluated.meshes.count == 1)
}

@MainActor
@Test func evaluationCacheMatchesOnlyItsExplicitModelingSettings() throws {
    let session = EditorSession()
    session.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    _ = try #require(session.createDefaultExtrudedRectangle())
    let cache = try #require(session.currentEvaluationCache)
    var changedSettingsDocument = session.document
    changedSettingsDocument.modelingSettings.tolerance.distance *= 2.0

    #expect(try cache.matches(document: session.document, generation: session.generation))
    #expect(try !cache.matches(document: changedSettingsDocument, generation: session.generation))
    #expect(try DocumentEvaluationContext(cache: cache).matches(
        document: session.document,
        generation: session.generation
    ))
}

private func approximatelyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-12
) -> Bool {
    abs(lhs - rhs) <= tolerance
}
