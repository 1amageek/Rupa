import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func sketchVertexOffsetInspectorStateAcceptsLineAndArcEndpoints() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let lineID = SketchEntityID()
    let arcID = SketchEntityID()

    let lineTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: lineID,
                handle: .lineEnd
            )
        )
    )
    let arcTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: arcID,
                handle: .arcStart
            )
        )
    )

    #expect(
        SketchVertexOffsetInspectorState(
            entityKind: "line",
            entityID: lineID,
            target: lineTarget
        )
        .handle == .lineEnd
    )
    #expect(
        SketchVertexOffsetInspectorState(
            entityKind: "arc",
            entityID: arcID,
            target: arcTarget
        )
        .handle == .arcStart
    )
}

@Test func sketchVertexOffsetInspectorStateRejectsNonVertexTargets() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let lineID = SketchEntityID()
    let otherID = SketchEntityID()
    let wholeLineTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: lineID))
    )
    let circleCenterTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: lineID,
                handle: .circleCenter
            )
        )
    )
    let mismatchedTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: otherID,
                handle: .lineStart
            )
        )
    )

    #expect(
        SketchVertexOffsetInspectorState(
            entityKind: "line",
            entityID: lineID,
            target: wholeLineTarget
        )
        .handle == nil
    )
    #expect(
        SketchVertexOffsetInspectorState(
            entityKind: "line",
            entityID: lineID,
            target: circleCenterTarget
        )
        .handle == nil
    )
    #expect(
        SketchVertexOffsetInspectorState(
            entityKind: "line",
            entityID: lineID,
            target: mismatchedTarget
        )
        .handle == nil
    )
}
