import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceTopologyEditInspectorStateBuilderClassifiesDirectEditTargets() {
    let sceneNodeID = SceneNodeID()
    let faceTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(.generatedTopology("body:face:top"))
    )
    let edgeTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(.generatedTopology("body:edge:top"))
    )
    let vertexTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(.generatedTopology("body:vertex:topLeft"))
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
    #expect(state.draftFaceTarget == nil)
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

@Test func workspaceTopologyEditInspectorStateBuilderRequiresSingleFaceAndVertexSelection() {
    let sceneNodeID = SceneNodeID()
    let firstFace = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let secondFace = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceBottom))
    let firstVertex = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(.generatedTopology("body:vertex:first"))
    )
    let secondVertex = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(.generatedTopology("body:vertex:second"))
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
    #expect(state.draftFaceTarget == nil)
    #expect(state.draftNeutralFaceTarget == nil)
    #expect(!state.canDraftFace)
    #expect(!state.canDeleteFaces)
    #expect(!state.canEditVertex)
}

@Test func workspaceTopologyEditInspectorStateBuilderCreatesDraftFacePairForTwoOrderedFaces() {
    let sceneNodeID = SceneNodeID()
    let targetFace = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(.generatedTopology("body:face:side"))
    )
    let neutralFace = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .face(.generatedTopology("body:face:bottom"))
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
    #expect(state.draftFaceTarget == targetFace)
    #expect(state.draftNeutralFaceTarget == neutralFace)
    #expect(state.canDraftFace)
    #expect(state.canDeleteFaces)
}

@Test func workspaceTopologyEditInspectorStateBuilderProjectsGeneratedEdgesOnce() {
    let sceneNodeID = SceneNodeID()
    let generatedEdge = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(.generatedTopology("body:edge:generated"))
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
