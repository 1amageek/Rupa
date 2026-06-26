import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func sketchCurveJoinInspectorStateAcceptsSameSketchLineCandidate() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let firstLineID = SketchEntityID()
    let secondLineID = SketchEntityID()
    let target = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: firstLineID))
    )
    let adjacentTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: secondLineID))
    )

    let state = SketchCurveJoinInspectorState(
        entityKind: "line",
        sourceFeatureID: featureID,
        entityID: firstLineID,
        target: target,
        joinedCurveSourceID: nil,
        selectedTargets: [target, adjacentTarget],
        entityKindsByTarget: [
            target: "line",
            adjacentTarget: "line",
        ]
    )

    #expect(state.joinAdjacentTarget == adjacentTarget)
    #expect(state.canJoin)
    #expect(!state.canUnjoin)
}

@Test func sketchCurveJoinInspectorStateRejectsUnsupportedJoinCandidates() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let otherFeatureID = FeatureID()
    let lineID = SketchEntityID()
    let otherLineID = SketchEntityID()
    let arcID = SketchEntityID()
    let target = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: lineID))
    )
    let sameEntityHandleTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: lineID,
                handle: .lineEnd
            )
        )
    )
    let otherSketchLineTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: otherFeatureID, entityID: otherLineID))
    )
    let arcTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: arcID))
    )

    let state = SketchCurveJoinInspectorState(
        entityKind: "line",
        sourceFeatureID: featureID,
        entityID: lineID,
        target: target,
        joinedCurveSourceID: nil,
        selectedTargets: [target, sameEntityHandleTarget, otherSketchLineTarget, arcTarget],
        entityKindsByTarget: [
            target: "line",
            sameEntityHandleTarget: "line",
            otherSketchLineTarget: "line",
            arcTarget: "arc",
        ]
    )

    #expect(state.joinAdjacentTarget == nil)
    #expect(!state.canJoin)
}

@Test func sketchCurveJoinInspectorStateEnablesUnjoinOnlyForJoinedLines() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let lineID = SketchEntityID()
    let target = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: lineID))
    )
    let joinedSourceID = JoinedCurveSourceID()

    let joinedLineState = SketchCurveJoinInspectorState(
        entityKind: "line",
        sourceFeatureID: featureID,
        entityID: lineID,
        target: target,
        joinedCurveSourceID: joinedSourceID,
        selectedTargets: [target],
        entityKindsByTarget: [target: "line"]
    )
    let joinedArcState = SketchCurveJoinInspectorState(
        entityKind: "arc",
        sourceFeatureID: featureID,
        entityID: lineID,
        target: target,
        joinedCurveSourceID: joinedSourceID,
        selectedTargets: [target],
        entityKindsByTarget: [target: "arc"]
    )

    #expect(joinedLineState.canUnjoin)
    #expect(!joinedArcState.canUnjoin)
}
