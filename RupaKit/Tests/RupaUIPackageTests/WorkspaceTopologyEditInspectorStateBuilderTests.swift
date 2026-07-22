import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceTopologyEditInspectorStateBuilderClassifiesDirectEditTargets() throws {
    let sceneNodeID = SceneNodeID()
    let faceTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(try workspaceTopologyFaceComponent(role: "body.face.top"))
    )
    let edgeTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(try workspaceTopologyEdgeComponent(role: "body.edge.top"))
    )
    let vertexTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(try workspaceTopologyVertexComponent(role: "body.vertex.topLeft"))
    )
    let regionTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .region(.profileRegion(featureID: FeatureID(), profileIndex: 0))
    )
    let builder = WorkspaceTopologyEditInspectorStateBuilder(
        selection: SelectionModel(selectedTargets: [faceTarget, edgeTarget, vertexTarget, regionTarget]),
        selectedTargetSummary: "4 targets",
        faceOffsetStepMeters: 0.001,
        edgeChamferStepMeters: 0.002,
        edgeFilletRadiusMeters: 0.003,
        vertexMoveStepMeters: 0.004,
        usesLockedRegionDistance: true,
        combinesRegions: true
    )

    let state = builder.state(for: [SceneNode(id: sceneNodeID, name: "Body")])

    #expect(state.isSingleNodeSelection)
    #expect(state.faceTarget == faceTarget)
    #expect(state.faceTargets == [faceTarget])
    #expect(state.draftFaceTargets.isEmpty)
    #expect(state.draftNeutralFaceTarget == nil)
    #expect(!state.canDraftFace)
    #expect(state.canDeleteFaces)
    #expect(state.edgeTargets == [edgeTarget])
    #expect(state.projectableEdgeTargets == [edgeTarget])
    #expect(state.vertexTarget == vertexTarget)
    #expect(state.regionTargets == [regionTarget])
    #expect(state.faceOffsetStepMeters == 0.001)
    #expect(state.edgeChamferStepMeters == 0.002)
    #expect(state.edgeFilletRadiusMeters == 0.003)
    #expect(state.vertexMoveStepMeters == 0.004)
    #expect(state.usesLockedRegionDistance)
    #expect(state.combinesRegions)
}

@Test func workspaceTopologyEditInspectorStateBuilderRequiresSingleFaceAndVertexSelection() throws {
    let sceneNodeID = SceneNodeID()
    let firstFace = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let secondFace = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceBottom))
    let firstVertex = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(try workspaceTopologyVertexComponent(role: "body.vertex.first"))
    )
    let secondVertex = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(try workspaceTopologyVertexComponent(role: "body.vertex.second"))
    )
    let builder = WorkspaceTopologyEditInspectorStateBuilder(
        selection: SelectionModel(selectedTargets: [firstFace, secondFace, firstVertex, secondVertex]),
        selectedTargetSummary: "4 targets",
        faceOffsetStepMeters: 0.001,
        edgeChamferStepMeters: 0.001,
        edgeFilletRadiusMeters: 0.001,
        vertexMoveStepMeters: 0.001,
        usesLockedRegionDistance: false,
        combinesRegions: false
    )

    let state = builder.state(for: [
        SceneNode(id: sceneNodeID, name: "Body"),
        SceneNode(name: "Other"),
    ])

    #expect(builder.faceTargets == [firstFace, secondFace])
    #expect(builder.vertexTargets == [firstVertex, secondVertex])
    #expect(builder.faceTarget == nil)
    #expect(builder.vertexTarget == nil)
    #expect(!state.isSingleNodeSelection)
    #expect(!state.canEditFace)
    #expect(state.draftFaceTargets.isEmpty)
    #expect(state.draftNeutralFaceTarget == nil)
    #expect(!state.canDraftFace)
    #expect(!state.canDeleteFaces)
    #expect(!state.canEditVertex)
}

@Test func workspaceTopologyEditInspectorStateBuilderCreatesDraftFacePairForTwoOrderedFaces() throws {
    let sceneNodeID = SceneNodeID()
    let targetFace = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(try workspaceTopologyFaceComponent(role: "body.face.side"))
    )
    let neutralFace = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(try workspaceTopologyFaceComponent(role: "body.face.bottom"))
    )
    let builder = WorkspaceTopologyEditInspectorStateBuilder(
        selection: SelectionModel(selectedTargets: [targetFace, neutralFace]),
        selectedTargetSummary: "2 targets",
        faceOffsetStepMeters: 0.001,
        edgeChamferStepMeters: 0.001,
        edgeFilletRadiusMeters: 0.001,
        vertexMoveStepMeters: 0.001,
        usesLockedRegionDistance: false,
        combinesRegions: false
    )

    let state = builder.state(for: [
        SceneNode(id: sceneNodeID, name: "Body"),
    ])

    #expect(state.faceTarget == nil)
    #expect(state.faceTargets == [targetFace, neutralFace])
    #expect(!state.canEditFace)
    #expect(state.draftFaceTargets == [targetFace])
    #expect(state.draftNeutralFaceTarget == neutralFace)
    #expect(state.canDraftFace)
    #expect(state.canDeleteFaces)
}

@Test func workspaceTopologyEditInspectorStateBuilderUsesLastFaceAsDraftNeutralForMultipleTargets() throws {
    let sceneNodeID = SceneNodeID()
    let firstTargetFace = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(try workspaceTopologyFaceComponent(role: "body.face.firstSide"))
    )
    let secondTargetFace = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(try workspaceTopologyFaceComponent(role: "body.face.secondSide"))
    )
    let neutralFace = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(try workspaceTopologyFaceComponent(role: "body.face.bottom"))
    )
    let builder = WorkspaceTopologyEditInspectorStateBuilder(
        selection: SelectionModel(selectedTargets: [firstTargetFace, secondTargetFace, neutralFace]),
        selectedTargetSummary: "3 targets",
        faceOffsetStepMeters: 0.001,
        edgeChamferStepMeters: 0.001,
        edgeFilletRadiusMeters: 0.001,
        vertexMoveStepMeters: 0.001,
        usesLockedRegionDistance: false,
        combinesRegions: false
    )

    let state = builder.state(for: [
        SceneNode(id: sceneNodeID, name: "Body"),
    ])

    #expect(state.faceTarget == nil)
    #expect(state.faceTargets == [firstTargetFace, secondTargetFace, neutralFace])
    #expect(state.draftFaceTargets == [firstTargetFace, secondTargetFace])
    #expect(state.draftNeutralFaceTarget == neutralFace)
    #expect(state.canDraftFace)
    #expect(state.canDeleteFaces)
}

@Test func workspaceTopologyEditInspectorStateBuilderProjectsGeneratedEdgesOnce() throws {
    let sceneNodeID = SceneNodeID()
    let generatedEdge = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(try workspaceTopologyEdgeComponent(role: "body.edge.generated"))
    )
    let semanticEdge = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(.bodyEdgeRightTop)
    )
    let builder = WorkspaceTopologyEditInspectorStateBuilder(
        selection: SelectionModel(selectedTargets: [generatedEdge, generatedEdge, semanticEdge]),
        selectedTargetSummary: "3 targets",
        faceOffsetStepMeters: 0.001,
        edgeChamferStepMeters: 0.001,
        edgeFilletRadiusMeters: 0.001,
        vertexMoveStepMeters: 0.001,
        usesLockedRegionDistance: false,
        combinesRegions: false
    )

    #expect(builder.edgeTargets == [generatedEdge, semanticEdge])
    #expect(builder.generatedEdgeProjectionTargets(from: builder.edgeTargets) == [generatedEdge])
}

private func workspaceTopologyFaceComponent(role: String) throws -> SelectionComponentID {
    try .stableTopology(StableSubshapeReference(
        subshapeID: SubshapeID(featureID: FeatureID(), role: role, ordinal: 0),
        geometrySignature: .face(FaceGeometrySignature(
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            orientation: .forward,
            loops: []
        ))
    ))
}

private func workspaceTopologyEdgeComponent(role: String) throws -> SelectionComponentID {
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

private func workspaceTopologyVertexComponent(role: String) throws -> SelectionComponentID {
    try .stableTopology(StableSubshapeReference(
        subshapeID: SubshapeID(featureID: FeatureID(), role: role, ordinal: 0),
        geometrySignature: .vertex(point: .origin)
    ))
}
