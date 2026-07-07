import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportActiveInteractionDragsReportsWhetherAnyDragIsActive() {
    var drags = ViewportActiveInteractionDrags()

    #expect(!drags.hasActiveDrag)

    drags.affordance = affordanceDragState()

    #expect(drags.hasActiveDrag)
}

@Test func viewportActiveInteractionDragsClearRemovesEveryDragWhenNoTargetIsPreserved() {
    var drags = ViewportActiveInteractionDrags(
        affordance: affordanceDragState(),
        sketchCurveHandle: sketchCurveHandleDragState()
    )

    drags.clear()

    #expect(!drags.hasActiveDrag)
    #expect(drags.affordance == nil)
    #expect(drags.sketchCurveHandle == nil)
}

@Test func viewportActiveInteractionDragsClearPreservesOnlyMatchingInteractionTarget() {
    let preserved = affordanceDragState()
    var drags = ViewportActiveInteractionDrags(
        affordance: preserved,
        sketchCurveHandle: sketchCurveHandleDragState()
    )

    drags.clear(except: .affordance(preserved.target))

    #expect(drags.affordance == preserved)
    #expect(drags.sketchCurveHandle == nil)
    #expect(drags.hasActiveDrag)
}

@Test func viewportActiveInteractionDragsClearDoesNotPreserveDifferentTargetOfSameKind() {
    let original = sketchCurveHandleDragState(entityID: SketchEntityID())
    let replacement = sketchCurveHandleTarget(entityID: SketchEntityID())
    var drags = ViewportActiveInteractionDrags(sketchCurveHandle: original)

    drags.clear(except: .sketchCurveHandle(replacement))

    #expect(drags.sketchCurveHandle == nil)
    #expect(!drags.hasActiveDrag)
}

private func affordanceDragState(featureID: FeatureID = FeatureID()) -> ViewportAffordanceDragState {
    ViewportAffordanceDragState(
        target: ViewportAffordanceTarget(
            featureID: featureID,
            action: .translate(.x)
        ),
        startPoint: .zero,
        baseEdits: [:],
        baseGroupEdit: nil
    )
}

private func sketchCurveHandleDragState(
    entityID: SketchEntityID = SketchEntityID()
) -> ViewportSketchCurveHandleDragState {
    ViewportSketchCurveHandleDragState(
        target: sketchCurveHandleTarget(entityID: entityID),
        startPoint: .zero,
        radiusMeters: 2.0,
        startAngleRadians: nil,
        endAngleRadians: nil
    )
}

private func sketchCurveHandleTarget(
    entityID: SketchEntityID = SketchEntityID()
) -> ViewportSketchCurveHandleTarget {
    ViewportSketchCurveHandleTarget(
        featureID: FeatureID(),
        entityID: entityID,
        target: SelectionTarget(sceneNodeID: SceneNodeID()),
        handle: .circleRadius,
        sketchPlane: .xy,
        center: .zero,
        radiusMeters: 1.0,
        startAngleRadians: nil,
        endAngleRadians: nil
    )
}
