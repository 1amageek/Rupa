import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceSketchCommandTargetResolverNormalizesSlotOpenCurveTargets() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let lineID = SketchEntityID()
    let arcID = SketchEntityID()
    let splineID = SketchEntityID()
    let resolver = WorkspaceSketchCommandTargetResolver()
    let lineEndpointTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: lineID,
                handle: .lineEnd
            )
        )
    )

    #expect(
        resolver.slotSourceCurveTarget(
            for: sketchCommandEntity(
                target: lineEndpointTarget,
                featureID: featureID,
                entityID: lineID,
                kind: "line"
            )
        ) == wholeSketchEntityTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: lineID)
    )
    #expect(
        resolver.slotSourceCurveTarget(
            for: sketchCommandEntity(
                sceneNodeID: sceneNodeID,
                featureID: featureID,
                entityID: arcID,
                kind: "arc"
            )
        ) == wholeSketchEntityTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: arcID)
    )
    #expect(
        resolver.slotSourceCurveTarget(
            for: sketchCommandEntity(
                sceneNodeID: sceneNodeID,
                featureID: featureID,
                entityID: splineID,
                kind: "spline"
            )
        ) == wholeSketchEntityTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: splineID)
    )
}

@Test func workspaceSketchCommandTargetResolverRejectsClosedOrPointSlotTargets() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let resolver = WorkspaceSketchCommandTargetResolver()

    #expect(
        resolver.slotSourceCurveTarget(
            for: sketchCommandEntity(
                sceneNodeID: sceneNodeID,
                featureID: featureID,
                entityID: SketchEntityID(),
                kind: "circle"
            )
        ) == nil
    )
    #expect(
        resolver.slotSourceCurveTarget(
            for: sketchCommandEntity(
                sceneNodeID: sceneNodeID,
                featureID: featureID,
                entityID: SketchEntityID(),
                kind: "point"
            )
        ) == nil
    )
    #expect(resolver.slotSourceCurveTarget(for: nil) == nil)
}

@Test func workspaceSketchCommandTargetResolverResolvesEntityFromResult() {
    let entity = sketchCommandEntity(
        sceneNodeID: SceneNodeID(),
        featureID: FeatureID(),
        entityID: SketchEntityID(),
        kind: "line"
    )
    let resolver = WorkspaceSketchCommandTargetResolver()
    let failure = EditorError(code: .referenceUnresolved, message: "Missing entity.")

    #expect(resolver.entity(from: .success(entity)) == entity)
    #expect(resolver.entity(from: .success(nil)) == nil)
    #expect(resolver.entity(from: .failure(failure)) == nil)
}

@Test func workspaceSketchCommandTargetResolverSelectsVertexOffsetEndpointTargets() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let lineID = SketchEntityID()
    let arcID = SketchEntityID()
    let resolver = WorkspaceSketchCommandTargetResolver()
    let lineEndpointTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: lineID,
                handle: .lineStart
            )
        )
    )
    let arcEndpointTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: arcID,
                handle: .arcEnd
            )
        )
    )

    #expect(
        resolver.vertexOffsetTarget(
            for: sketchCommandEntity(
                target: lineEndpointTarget,
                featureID: featureID,
                entityID: lineID,
                kind: "line"
            )
        ) == lineEndpointTarget
    )
    #expect(
        resolver.vertexOffsetHandle(
            for: sketchCommandEntity(
                target: arcEndpointTarget,
                featureID: featureID,
                entityID: arcID,
                kind: "arc"
            )
        ) == .arcEnd
    )
}

@Test func workspaceSketchCommandTargetResolverRejectsUnsupportedVertexOffsetTargets() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let lineID = SketchEntityID()
    let resolver = WorkspaceSketchCommandTargetResolver()
    let wholeLineTarget = wholeSketchEntityTarget(
        sceneNodeID: sceneNodeID,
        featureID: featureID,
        entityID: lineID
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

    #expect(
        resolver.vertexOffsetTarget(
            for: sketchCommandEntity(
                target: wholeLineTarget,
                featureID: featureID,
                entityID: lineID,
                kind: "line"
            )
        ) == nil
    )
    #expect(
        resolver.vertexOffsetTarget(
            for: sketchCommandEntity(
                target: circleCenterTarget,
                featureID: featureID,
                entityID: lineID,
                kind: "line"
            )
        ) == nil
    )
    #expect(resolver.vertexOffsetTarget(for: nil) == nil)
}

private func sketchCommandEntity(
    sceneNodeID: SceneNodeID,
    featureID: FeatureID,
    entityID: SketchEntityID,
    kind: String
) -> InspectorSketchEntity {
    sketchCommandEntity(
        target: wholeSketchEntityTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: entityID),
        featureID: featureID,
        entityID: entityID,
        kind: kind
    )
}

private func sketchCommandEntity(
    target: SelectionTarget,
    featureID: FeatureID,
    entityID: SketchEntityID,
    kind: String
) -> InspectorSketchEntity {
    InspectorSketchEntity(
        target: target,
        sourceFeatureID: featureID,
        entityID: entityID,
        sourceFeatureName: "Sketch",
        entityKind: kind
    )
}

private func wholeSketchEntityTarget(
    sceneNodeID: SceneNodeID,
    featureID: FeatureID,
    entityID: SketchEntityID
) -> SelectionTarget {
    SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))
    )
}
