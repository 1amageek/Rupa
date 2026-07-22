import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceSelectionTargetClassificationGroupsTargetsByComponent() throws {
    let sceneNodeID = SceneNodeID()
    let objectTarget = SelectionTarget(sceneNodeID: sceneNodeID)
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let edgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let vertexTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(try workspaceClassificationVertexComponent(role: "body.vertex.first"))
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

@Test func workspaceSelectionTargetClassificationBuildsDimensionTargets() throws {
    let sceneNodeID = SceneNodeID()
    let objectTarget = SelectionTarget(sceneNodeID: sceneNodeID)
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let semanticEdgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let generatedEdgeTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(try workspaceClassificationEdgeComponent(role: "body.edge.generated"))
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

@Test func workspaceSelectionTargetClassificationDeduplicatesGeneratedEdgesForProjection() throws {
    let sceneNodeID = SceneNodeID()
    let generatedEdgeTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(try workspaceClassificationEdgeComponent(role: "body.edge.generated"))
    )
    let semanticEdgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let classification = WorkspaceSelectionTargetClassification(
        targets: [generatedEdgeTarget, generatedEdgeTarget, semanticEdgeTarget]
    )

    #expect(classification.edgeTargets == [generatedEdgeTarget, generatedEdgeTarget, semanticEdgeTarget])
    #expect(classification.generatedEdgeTargets == [generatedEdgeTarget])
    #expect(classification.generatedEdgeTargets(from: classification.edgeTargets) == [generatedEdgeTarget])
}

private func workspaceClassificationEdgeComponent(role: String) throws -> SelectionComponentID {
    try .stableTopology(StableSubshapeReference(
        subshapeID: SubshapeID(featureID: FeatureID(), role: role, ordinal: 0),
        geometrySignature: .edge(CurveSpanGeometrySignature(
            curve: .line(Line3D(origin: .origin, direction: .unitX)),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: .origin,
            endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
        ))
    ))
}

private func workspaceClassificationVertexComponent(role: String) throws -> SelectionComponentID {
    try .stableTopology(StableSubshapeReference(
        subshapeID: SubshapeID(featureID: FeatureID(), role: role, ordinal: 0),
        geometrySignature: .vertex(point: .origin)
    ))
}
