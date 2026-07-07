import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportActiveInteractionDragsReportsWhetherAnyDragIsActive() {
    var drags = ViewportActiveInteractionDrags()

    #expect(!drags.hasActiveDrag)
    #expect(drags.nextFinishKind == nil)

    drags.affordance = affordanceDragState()

    #expect(drags.hasActiveDrag)
    #expect(drags.nextFinishKind == .affordance)
}

@Test func viewportActiveInteractionDragsNextFinishKindFollowsViewportCommitPrecedence() {
    let drags = ViewportActiveInteractionDrags(
        affordance: affordanceDragState(),
        sketchCurveHandle: sketchCurveHandleDragState(),
        sketchDimension: sketchDimensionDragState()
    )

    #expect(drags.nextFinishKind == ViewportActiveInteractionDragKind.sketchCurveHandle)
}

@Test func viewportActiveInteractionDragKindFinishPrecedenceIsStableAndUnique() {
    let precedence = ViewportActiveInteractionDragKind.finishPrecedence

    #expect(precedence == ViewportActiveInteractionDragKind.allCases)
    #expect(precedence.first == .sketchCurveHandle)
    #expect(precedence.last == .affordance)
    #expect(Set(precedence).count == precedence.count)
}

@Test func viewportActiveInteractionDragsKeepsOnlyOneActiveDragWhenSettingNewDrag() {
    var drags = ViewportActiveInteractionDrags()

    drags.affordance = affordanceDragState()
    drags.sketchCurveHandle = sketchCurveHandleDragState()

    #expect(drags.affordance == nil)
    #expect(drags.sketchCurveHandle != nil)
    #expect(drags.hasActiveDrag)
    #expect(drags.nextFinishKind == .sketchCurveHandle)
}

@Test func viewportActiveInteractionDragsClearsOnlyMatchingActiveDragWhenSettingNil() {
    var drags = ViewportActiveInteractionDrags()

    drags.affordance = affordanceDragState()
    drags.sketchCurveHandle = sketchCurveHandleDragState()
    drags.affordance = nil

    #expect(drags.sketchCurveHandle != nil)
    #expect(drags.nextFinishKind == .sketchCurveHandle)

    drags.sketchCurveHandle = nil

    #expect(!drags.hasActiveDrag)
    #expect(drags.nextFinishKind == nil)
}

@Test func viewportActiveInteractionDragsInitializerUsesFinishPrecedenceForLegacyMultipleInputs() {
    let drags = ViewportActiveInteractionDrags(
        affordance: affordanceDragState(),
        sketchCurveHandle: sketchCurveHandleDragState(),
        sketchDimension: sketchDimensionDragState()
    )

    #expect(drags.sketchCurveHandle != nil)
    #expect(drags.sketchDimension == nil)
    #expect(drags.affordance == nil)
    #expect(drags.nextFinishKind == .sketchCurveHandle)
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
    var drags = ViewportActiveInteractionDrags(affordance: preserved)

    drags.clear(except: .affordance(preserved.target))

    #expect(drags.affordance == preserved)
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

private func sketchDimensionDragState(
    entityID: SketchEntityID = SketchEntityID()
) -> ViewportSketchDimensionDragState {
    ViewportSketchDimensionDragState(
        target: ViewportSketchDimensionTarget(
            featureID: FeatureID(),
            entityID: entityID,
            target: SelectionTarget(sceneNodeID: SceneNodeID()),
            kind: .length,
            sketchPlane: .xy,
            baselineValue: 1.0,
            start: CGPoint(x: 0.0, y: 0.0),
            end: CGPoint(x: 1.0, y: 0.0),
            center: nil,
            radiusMeters: nil,
            startAngleRadians: nil,
            endAngleRadians: nil
        ),
        startPoint: .zero,
        value: 2.0
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
