import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportSlotWidthAffordanceServiceCreatesLineCandidate() throws {
    let layout = slotWidthTestLayout()
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let target = slotWidthSourceTarget(featureID: featureID, entityID: entityID)

    let candidate = try #require(
        ViewportSlotWidthAffordanceService().candidate(
            for: target,
            primitives: [
                .line(
                    entityID: entityID,
                    start: CGPoint(x: 0.0, y: 0.0),
                    end: CGPoint(x: 2.0, y: 0.0)
                ),
            ],
            widthMeters: 0.4,
            layout: layout
        )
    )

    #expect(candidate.target.featureID == featureID)
    #expect(candidate.target.entityID == entityID)
    #expect(abs(candidate.geometry.baseModelPoint.x - 1.0) < 1.0e-12)
    #expect(abs(candidate.geometry.baseModelPoint.y) < 1.0e-12)
}

@Test func viewportSlotWidthAffordanceServiceCreatesArcCandidateAtArcMidpoint() throws {
    let layout = slotWidthTestLayout()
    let entityID = SketchEntityID()
    let geometry = try #require(
        ViewportSlotWidthAffordanceService().geometry(
            for: .arc(
                entityID: entityID,
                center: CGPoint(x: 0.0, y: 0.0),
                radiusMeters: 1.0,
                startAngleRadians: 0.0,
                endAngleRadians: Double.pi
            ),
            widthMeters: 1.2,
            layout: layout
        )
    )

    let tip = geometry.projectedTip(layout: layout, widthMeters: 1.6)

    #expect(abs(geometry.baseModelPoint.x) < 1.0e-12)
    #expect(abs(geometry.baseModelPoint.y - 1.0) < 1.0e-12)
    #expect(tip.x.isFinite)
    #expect(tip.y.isFinite)
    #expect(hypot(geometry.modelDirection.x, geometry.modelDirection.y) > 0.99)
}

@Test func viewportSlotWidthAffordanceServiceCreatesSplineCandidateFromPolylineMidpoint() throws {
    let layout = slotWidthTestLayout()
    let entityID = SketchEntityID()
    let geometry = try #require(
        ViewportSlotWidthAffordanceService().geometry(
            for: .spline(
                entityID: entityID,
                points: [
                    CGPoint(x: 0.0, y: 0.0),
                    CGPoint(x: 1.0, y: 0.0),
                    CGPoint(x: 1.0, y: 1.0),
                ],
                controlPoints: [],
                sketchPlane: .xy
            ),
            widthMeters: 0.2,
            layout: layout
        )
    )

    #expect(abs(geometry.baseModelPoint.x - 1.0) < 1.0e-12)
    #expect(abs(geometry.baseModelPoint.y) < 1.0e-12)
}

@Test func viewportSlotWidthAffordanceServiceRejectsClosedOrDegenerateSources() {
    let layout = slotWidthTestLayout()
    let service = ViewportSlotWidthAffordanceService()
    let entityID = SketchEntityID()

    #expect(
        service.geometry(
            for: .circle(entityID: entityID, center: CGPoint(x: 0.0, y: 0.0), radiusMeters: 1.0),
            widthMeters: 0.2,
            layout: layout
        ) == nil
    )
    #expect(
        service.geometry(
            for: .point(entityID: entityID, point: CGPoint(x: 0.0, y: 0.0)),
            widthMeters: 0.2,
            layout: layout
        ) == nil
    )
    #expect(
        service.geometry(
            for: .spline(entityID: entityID, points: [CGPoint(x: 0.0, y: 0.0)], controlPoints: [], sketchPlane: .xy),
            widthMeters: 0.2,
            layout: layout
        ) == nil
    )
}

private func slotWidthTestLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: -2.0, y: -2.0, width: 4.0, height: 4.0),
        size: CGSize(width: 800.0, height: 600.0)
    )
}

private func slotWidthSourceTarget(
    featureID: FeatureID,
    entityID: SketchEntityID
) -> ViewportSlotWidthSourceTarget {
    let sceneNodeID = SceneNodeID()
    return ViewportSlotWidthSourceTarget(
        featureID: featureID,
        entityID: entityID,
        target: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))
        )
    )
}
