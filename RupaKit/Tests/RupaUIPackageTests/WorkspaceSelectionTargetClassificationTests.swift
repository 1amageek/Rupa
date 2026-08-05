import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceSelectionTargetClassificationGroupsTargetsByComponent() {
    let sceneNodeID = SceneNodeID()
    let objectTarget = SelectionTarget(sceneNodeID: sceneNodeID)
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let edgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let vertexTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(.generatedTopology(generatedTopologyTestSubshapeID("body:vertex:first")))
    )
    let sketchTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: FeatureID(), entityID: SketchEntityID()))
    )
    let regionTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .region(.profileRegion(featureID: FeatureID(), profileIndex: 0))
    )
    let classification = WorkspaceSelectionTargetClassification(
        targets: [objectTarget, faceTarget, edgeTarget, vertexTarget, sketchTarget, regionTarget]
    )

    #expect(classification.objectTargets == [objectTarget])
    #expect(classification.faceTargets == [faceTarget])
    #expect(classification.edgeTargets == [edgeTarget])
    #expect(classification.vertexTargets == [vertexTarget])
    #expect(classification.sketchEntityTargets == [sketchTarget])
    #expect(classification.regionTargets == [regionTarget])
}

@Test func workspaceSelectionTargetClassificationBuildsDimensionTargets() {
    let sceneNodeID = SceneNodeID()
    let objectTarget = SelectionTarget(sceneNodeID: sceneNodeID)
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let semanticEdgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let generatedEdgeTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(.generatedTopology(generatedTopologyTestSubshapeID("body:edge:generated")))
    )
    let sketchTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(.sketchEntity(featureID: FeatureID(), entityID: SketchEntityID()))
    )
    let classification = WorkspaceSelectionTargetClassification(
        targets: [faceTarget, objectTarget, semanticEdgeTarget, generatedEdgeTarget, sketchTarget]
    )

    #expect(classification.objectDimensionTargets == [faceTarget, objectTarget])
    #expect(classification.sketchDimensionTargets == [generatedEdgeTarget, sketchTarget])
}

@Test func workspaceSelectionTargetClassificationDeduplicatesGeneratedEdgesForProjection() {
    let sceneNodeID = SceneNodeID()
    let generatedEdgeTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(.generatedTopology(generatedTopologyTestSubshapeID("body:edge:generated")))
    )
    let semanticEdgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let classification = WorkspaceSelectionTargetClassification(
        targets: [generatedEdgeTarget, generatedEdgeTarget, semanticEdgeTarget]
    )

    #expect(classification.edgeTargets == [generatedEdgeTarget, generatedEdgeTarget, semanticEdgeTarget])
    #expect(classification.generatedEdgeTargets == [generatedEdgeTarget])
    #expect(classification.generatedEdgeTargets(from: classification.edgeTargets) == [generatedEdgeTarget])
}


/// Shared feature identity so equal role strings map to equal subshape IDs
/// within this file's tests.
private let generatedTopologyTestFeatureID = FeatureID()

private func generatedTopologyTestSubshapeID(_ role: String) -> SubshapeID {
    SubshapeID(
        featureID: generatedTopologyTestFeatureID,
        role: role,
        ordinal: 0
    )
}
