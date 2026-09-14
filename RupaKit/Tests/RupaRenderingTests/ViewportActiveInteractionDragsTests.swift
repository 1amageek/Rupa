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

@Test func viewportActiveInteractionDragKindFinishPrecedenceCoversEveryKindOnce() {
    let precedence = ViewportActiveInteractionDragKind.finishPrecedence

    #expect(precedence == ViewportActiveInteractionDragKind.allCases)
    #expect(Set(precedence).count == precedence.count)
}

@Test func viewportActiveInteractionDragCandidatesResolveTheClaimedDrag() {
    let candidates = ViewportActiveInteractionDragCandidates(affordance: affordanceDragState())

    #expect(candidates.firstActiveDrag?.kind == .affordance)
    #expect(ViewportActiveInteractionDragCandidates().firstActiveDrag == nil)
}

@Test func viewportActiveInteractionDragsClearsTheActiveDragWhenSettingNil() {
    var drags = ViewportActiveInteractionDrags(affordance: affordanceDragState())

    drags.affordance = nil

    #expect(!drags.hasActiveDrag)
    #expect(drags.nextFinishKind == nil)
}

@Test func viewportActiveInteractionDragsClearRemovesTheDragWhenNoTargetIsPreserved() {
    var drags = ViewportActiveInteractionDrags(affordance: affordanceDragState())

    drags.clear()

    #expect(!drags.hasActiveDrag)
    #expect(drags.affordance == nil)
}

@Test func viewportActiveInteractionDragsClearPreservesOnlyMatchingInteractionTarget() {
    let preserved = affordanceDragState()
    var drags = ViewportActiveInteractionDrags(affordance: preserved)

    drags.clear(except: .affordance(preserved.target))

    #expect(drags.affordance == preserved)
    #expect(drags.hasActiveDrag)
}

@Test func viewportActiveInteractionDragsClearDoesNotPreserveADifferentTargetOfTheSameKind() {
    let original = affordanceDragState()
    let replacement = affordanceDragState()
    var drags = ViewportActiveInteractionDrags(affordance: original)

    drags.clear(except: .affordance(replacement.target))

    #expect(drags.affordance == nil)
    #expect(!drags.hasActiveDrag)
}

@Test func viewportInteractionTargetReportsActiveDragKindForItsClaim() {
    let target = affordanceDragState().target

    #expect(ViewportInteractionTarget.affordance(target).activeDragKind == .affordance)
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

@Test func viewportInteractionDragFinishResolverFinishesPendingTargetWithoutActiveDrag() {
    let request = ViewportInteractionDragFinishResolver.request(
        pendingTarget: .affordance(affordanceDragState().target),
        activeInteractionDrags: ViewportActiveInteractionDrags()
    )

    #expect(request == .finish(.affordance))
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
