import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func modelingToleranceTracksWorkspaceScaleRange() {
    let micro = ModelingTolerance.workspaceScaleAware(
        for: WorkspaceScalePreset.microFabrication.rulerConfiguration
    )
    let precision = ModelingTolerance.workspaceScaleAware(
        for: WorkspaceScalePreset.precisionMechanical.rulerConfiguration
    )
    let architecture = ModelingTolerance.workspaceScaleAware(
        for: WorkspaceScalePreset.architecture.rulerConfiguration
    )
    let site = ModelingTolerance.workspaceScaleAware(
        for: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )

    #expect(micro.distance == 1.0e-8)
    #expect(precision.distance == 1.0e-8)
    #expect(architecture.distance == 2.0e-6)
    #expect(site.distance == 1.0e-4)
    #expect(micro.angle == ModelingTolerance.standard.angle)
    #expect(site.angle == ModelingTolerance.standard.angle)
}

@Test func modelingToleranceClampsWorkspaceScaleExtremes() {
    let smallest = ModelingTolerance.workspaceScaleAware(
        for: RulerConfiguration(
            displayUnit: .micrometer,
            minorTickMeters: RulerConfiguration.minorTickMetersRange.lowerBound,
            majorTickMeters: RulerConfiguration.majorTickMetersRange.lowerBound,
            visibleSpanMeters: RulerConfiguration.visibleSpanMetersRange.lowerBound
        )
    )
    let largest = ModelingTolerance.workspaceScaleAware(
        for: RulerConfiguration(
            displayUnit: .kilometer,
            minorTickMeters: 10_000.0,
            majorTickMeters: 100_000.0,
            visibleSpanMeters: RulerConfiguration.visibleSpanMetersRange.upperBound
        )
    )

    #expect(smallest.distance == 1.0e-8)
    #expect(largest.distance == 1.0e-3)
}

@MainActor
@Test func modelingDefaultPipelineEvaluatesSubMicronGeometryAtMicroScale() throws {
    var document = DesignDocument.empty(named: "Micro Geometry")
    try document.setRulerConfiguration(WorkspaceScalePreset.microFabrication.rulerConfiguration)
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
@Test func evaluationCacheMatchesWithWorkspaceScaleAwareTolerance() throws {
    let session = EditorSession()
    session.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    _ = try #require(session.createDefaultExtrudedRectangle())
    let cache = try #require(session.currentEvaluationCache)

    #expect(try cache.matches(document: session.document, generation: session.generation))
    #expect(try DocumentEvaluationContext(cache: cache).matches(
        document: session.document,
        generation: session.generation
    ))
}
