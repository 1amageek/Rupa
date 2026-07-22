import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Test func deleteBodyFacesCreatesSourceOwnedSheetBodyFromGeneratedFace() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(faceDeleteSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let faceEntry = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.generatedRole == "startFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let result = try session.execute(
        .deleteBodyFaces(targets: [target]),
        expectedGeneration: DocumentGeneration(1)
    )

    let deleteFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let deleteSceneNodeID = try #require(faceDeleteSceneNodeID(for: deleteFeatureID, in: session.document))
    let deleteFeature = try #require(session.document.cadDocument.designGraph.nodes[deleteFeatureID])
    guard case let .faceDelete(faceDelete) = deleteFeature.operation else {
        Issue.record("Delete Face command should create a FaceDelete feature.")
        return
    }
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let measurement = try MeasurementService(
        tolerance: session.document.modelingSettings.tolerance
    ).measure(document: session.document, ruler: session.workspaceState.ruler)
    let carriedFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == deleteSceneNodeID.description &&
            $0.generatedRole == "faceDelete" &&
            $0.subshapeRole == "carriedFace"
    }

    #expect(result.commandName == "deleteBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(deleteFeature.outputs == [FeatureOutput(role: .sheet)])
    #expect(faceDelete.target.featureID == bodyFeatureID)
    #expect(faceDelete.faces == [faceEntry.stableReference])
    #expect(body.kind == .sheet)
    #expect(afterTopology.counts.faceCount == 5)
    #expect(afterTopology.entries.contains {
        $0.stableReference == faceEntry.stableReference
    } == false)
    #expect(carriedFaces.count == 5)
    #expect(measurement.counts.sheets == 1)
    #expect(measurement.sheets.first?.featureID == deleteFeatureID.description)
    #expect((measurement.sheets.first?.surfaceAreaSquareMeters ?? 0.0) > 0.0)
    #expect(session.document.productMetadata.sceneNodes[deleteSceneNodeID]?.object?.geometryRole == .surface)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func deleteBodyFacesRejectsObjectTargetsBeforeMutation() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(faceDeleteSceneNodeID(for: bodyFeatureID, in: session.document))

    do {
        _ = try session.execute(
            .deleteBodyFaces(targets: [SelectionTarget(sceneNodeID: bodyNodeID)]),
            expectedGeneration: DocumentGeneration(1)
        )
        Issue.record("Delete Face should reject non-face object targets.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.last == bodyFeatureID)
    #expect(session.evaluationStatus == .valid)
}

private func faceDeleteSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference?.featureID == featureID
    }?.key
}
