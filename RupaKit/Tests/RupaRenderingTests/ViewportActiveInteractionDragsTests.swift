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

@Test func viewportActiveInteractionDragsNextFinishKindFollowsViewportCommitPrecedence() throws {
    let drags = ViewportActiveInteractionDrags(
        affordance: affordanceDragState(),
        splineControlPointSlide: try splineControlPointSlideDragState(),
        regionOffset: try regionOffsetDragState()
    )

    #expect(drags.nextFinishKind == ViewportActiveInteractionDragKind.splineControlPointSlide)
}

@Test func viewportActiveInteractionDragKindFinishPrecedenceIsStableAndUnique() {
    let precedence = ViewportActiveInteractionDragKind.finishPrecedence

    #expect(precedence == ViewportActiveInteractionDragKind.allCases)
    #expect(precedence.first == .splineControlPointSlide)
    #expect(precedence.last == .affordance)
    #expect(Set(precedence).count == precedence.count)
}

@Test func viewportActiveInteractionDragCandidatesUseFinishPrecedenceForFirstActiveDrag() throws {
    let candidates = ViewportActiveInteractionDragCandidates(
        affordance: affordanceDragState(),
        splineControlPointSlide: try splineControlPointSlideDragState(),
        regionOffset: try regionOffsetDragState()
    )

    #expect(candidates.firstActiveDrag?.kind == .splineControlPointSlide)
}

@Test func viewportActiveInteractionDragsKeepsOnlyOneActiveDragWhenSettingNewDrag() throws {
    var drags = ViewportActiveInteractionDrags()

    drags.affordance = affordanceDragState()
    drags.splineControlPointSlide = try splineControlPointSlideDragState()

    #expect(drags.affordance == nil)
    #expect(drags.splineControlPointSlide != nil)
    #expect(drags.hasActiveDrag)
    #expect(drags.nextFinishKind == .splineControlPointSlide)
}

@Test func viewportActiveInteractionDragsClearsOnlyMatchingActiveDragWhenSettingNil() throws {
    var drags = ViewportActiveInteractionDrags()

    drags.affordance = affordanceDragState()
    drags.splineControlPointSlide = try splineControlPointSlideDragState()
    drags.affordance = nil

    #expect(drags.splineControlPointSlide != nil)
    #expect(drags.nextFinishKind == .splineControlPointSlide)

    drags.splineControlPointSlide = nil

    #expect(!drags.hasActiveDrag)
    #expect(drags.nextFinishKind == nil)
}

@Test func viewportActiveInteractionDragsInitializerUsesFinishPrecedenceForLegacyMultipleInputs() throws {
    let drags = ViewportActiveInteractionDrags(
        affordance: affordanceDragState(),
        splineControlPointSlide: try splineControlPointSlideDragState(),
        regionOffset: try regionOffsetDragState()
    )

    #expect(drags.splineControlPointSlide != nil)
    #expect(drags.regionOffset == nil)
    #expect(drags.affordance == nil)
    #expect(drags.nextFinishKind == .splineControlPointSlide)
}

@Test func viewportActiveInteractionDragsClearRemovesEveryDragWhenNoTargetIsPreserved() throws {
    var drags = ViewportActiveInteractionDrags(
        affordance: affordanceDragState(),
        splineControlPointSlide: try splineControlPointSlideDragState()
    )

    drags.clear()

    #expect(!drags.hasActiveDrag)
    #expect(drags.affordance == nil)
    #expect(drags.splineControlPointSlide == nil)
}

@Test func viewportActiveInteractionDragsClearPreservesOnlyMatchingInteractionTarget() {
    let preserved = affordanceDragState()
    var drags = ViewportActiveInteractionDrags(affordance: preserved)

    drags.clear(except: .affordance(preserved.target))

    #expect(drags.affordance == preserved)
    #expect(drags.hasActiveDrag)
}

@Test func viewportActiveInteractionDragsClearDoesNotPreserveDifferentTargetOfSameKind() throws {
    let original = try splineControlPointSlideDragState(entityID: SketchEntityID())
    let replacement = try splineControlPointSlideHandleTarget(entityID: SketchEntityID())
    var drags = ViewportActiveInteractionDrags(splineControlPointSlide: original)

    drags.clear(except: .splineControlPointSlide(replacement))

    #expect(drags.splineControlPointSlide == nil)
    #expect(!drags.hasActiveDrag)
}

@Test func viewportInteractionTargetReportsActiveDragKindForDragTargets() throws {
    let slideTarget = try splineControlPointSlideHandleTarget()
    let affordanceTarget = affordanceDragState().target

    #expect(
        ViewportInteractionTarget.splineControlPointSlide(slideTarget).activeDragKind
            == .splineControlPointSlide
    )
    #expect(ViewportInteractionTarget.affordance(affordanceTarget).activeDragKind == .affordance)
}

@Test func viewportInteractionDragFinishResolverReturnsNoneWithoutPendingOrActiveDrag() {
    let request = ViewportInteractionDragFinishResolver.request(
        pendingTarget: nil,
        activeInteractionDrags: ViewportActiveInteractionDrags()
    )

    #expect(request == .none)
}

@Test func viewportInteractionDragFinishResolverFinishesActiveDragWithoutPendingTarget() {
    let request = ViewportInteractionDragFinishResolver.request(
        pendingTarget: nil,
        activeInteractionDrags: ViewportActiveInteractionDrags(affordance: affordanceDragState())
    )

    #expect(request == .finish(.affordance))
}

@Test func viewportInteractionDragFinishResolverPrefersPendingTargetOverActiveDrag() throws {
    let request = ViewportInteractionDragFinishResolver.request(
        pendingTarget: .splineControlPointSlide(try splineControlPointSlideHandleTarget()),
        activeInteractionDrags: ViewportActiveInteractionDrags(affordance: affordanceDragState())
    )

    #expect(request == .finish(.splineControlPointSlide))
}

private struct ViewportActiveInteractionDragFixtureError: Error {}

private func fixtureLayout() -> ViewportLayout {
    ViewportLayout(
        modelBounds: CGRect(x: -0.004, y: -0.004, width: 0.012, height: 0.012),
        size: CGSize(width: 800.0, height: 600.0)
    )
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

private func splineControlPointSlideHandleTarget(
    entityID: SketchEntityID = SketchEntityID()
) throws -> ViewportSplineControlPointSlideHandleTarget {
    guard let geometry = ViewportSplineControlPointSlideAffordanceGeometry(
        controlPoints: [
            CGPoint(x: 0.000, y: 0.000),
            CGPoint(x: 0.002, y: 0.000),
            CGPoint(x: 0.004, y: 0.000),
        ],
        selectedIndexes: [1],
        direction: .positiveU,
        layout: fixtureLayout()
    ) else {
        throw ViewportActiveInteractionDragFixtureError()
    }
    return ViewportSplineControlPointSlideHandleTarget(
        featureID: FeatureID(),
        entityID: entityID,
        target: SelectionTarget(sceneNodeID: SceneNodeID()),
        controlPointIndexes: [1],
        direction: .positiveU,
        geometry: geometry
    )
}

private func splineControlPointSlideDragState(
    entityID: SketchEntityID = SketchEntityID()
) throws -> ViewportSplineControlPointSlideDragState {
    ViewportSplineControlPointSlideDragState(
        target: try splineControlPointSlideHandleTarget(entityID: entityID),
        startPoint: .zero,
        distanceMeters: 0.001
    )
}

private func regionOffsetDragState() throws -> ViewportRegionOffsetDragState {
    guard let geometry = ViewportRegionOffsetAffordanceGeometry(
        points: [
            CGPoint(x: 0.000, y: 0.000),
            CGPoint(x: 0.004, y: 0.000),
            CGPoint(x: 0.004, y: 0.004),
            CGPoint(x: 0.000, y: 0.004),
        ],
        layout: fixtureLayout()
    ) else {
        throw ViewportActiveInteractionDragFixtureError()
    }
    return ViewportRegionOffsetDragState(
        target: ViewportRegionOffsetHandleTarget(
            featureID: FeatureID(),
            componentID: SelectionComponentID(rawValue: "profileRegion:0"),
            target: SelectionTarget(sceneNodeID: SceneNodeID()),
            geometry: geometry
        ),
        startPoint: .zero,
        distanceMeters: 0.001
    )
}
