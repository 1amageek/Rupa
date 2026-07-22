import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func draftBodyFacesCreatesSourceOwnedSolidBodyFromGeneratedFaces() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(draftSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let targetEntry = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodySceneNodeID.description &&
            $0.generatedRole == "sideFace"
    })
    let neutralEntry = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodySceneNodeID.description &&
            $0.generatedRole == "startFace"
    })
    let target = try #require(targetEntry.selectionTarget())
    let neutralTarget = try #require(neutralEntry.selectionTarget())

    let result = try session.execute(
        .draftBodyFaces(
            targets: [target],
            neutralTarget: neutralTarget,
            angle: .angle(10.0, .degree)
        ),
        expectedGeneration: DocumentGeneration(1)
    )

    let draftFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let draftNodeID = try #require(draftSceneNodeID(for: draftFeatureID, in: session.document))
    let draftFeature = try #require(session.document.cadDocument.designGraph.nodes[draftFeatureID])
    guard case let .faceDraft(faceDraft) = draftFeature.operation else {
        Issue.record("Draft Face command should create a FaceDraft feature.")
        return
    }
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let measurement = try MeasurementService(
        tolerance: session.document.modelingSettings.tolerance
    ).measure(document: session.document, ruler: session.workspaceState.ruler)
    let draftFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == draftNodeID.description &&
            $0.generatedRole == "faceDraft"
    }

    #expect(result.commandName == "draftBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(draftFeature.outputs == [FeatureOutput(role: .body)])
    #expect(faceDraft.target.featureID == bodyFeatureID)
    #expect(faceDraft.faces == [targetEntry.stableReference])
    #expect(faceDraft.neutralFace == neutralEntry.stableReference)
    #expect(body.kind == .solid)
    #expect(afterTopology.counts.faceCount == 6)
    #expect(draftFaces.count == 6)
    #expect(measurement.counts.solids == 1)
    #expect(measurement.solids.first?.featureID == draftFeatureID.description)
    #expect((measurement.solids.first?.volumeCubicMeters ?? 0.0) > 0.0)
    #expect(session.document.productMetadata.sceneNodes[draftNodeID]?.object?.geometryRole == .solid)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func draftBodyFacesCreatesSourceOwnedSolidBodyFromMultipleGeneratedFaces() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(draftSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let targetEntries = topology.entries
        .filter {
            $0.kind == .face &&
                $0.sceneNodeID == bodySceneNodeID.description &&
                $0.generatedRole == "sideFace"
        }
        .sorted { ($0.index ?? -1) < ($1.index ?? -1) }
    let firstTarget = try #require(targetEntries.first?.selectionTarget())
    let secondTarget = try #require(targetEntries.dropFirst().first?.selectionTarget())
    let neutralEntry = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodySceneNodeID.description &&
            $0.generatedRole == "startFace"
    })
    let neutralTarget = try #require(neutralEntry.selectionTarget())

    let result = try session.execute(
        .draftBodyFaces(
            targets: [firstTarget, secondTarget],
            neutralTarget: neutralTarget,
            angle: .angle(10.0, .degree)
        ),
        expectedGeneration: DocumentGeneration(1)
    )

    let draftFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let draftNodeID = try #require(draftSceneNodeID(for: draftFeatureID, in: session.document))
    let draftFeature = try #require(session.document.cadDocument.designGraph.nodes[draftFeatureID])
    guard case let .faceDraft(faceDraft) = draftFeature.operation else {
        Issue.record("Draft Face command should create a FaceDraft feature.")
        return
    }
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let measurement = try MeasurementService(
        tolerance: session.document.modelingSettings.tolerance
    ).measure(document: session.document, ruler: session.workspaceState.ruler)
    let draftFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == draftNodeID.description &&
            $0.generatedRole == "faceDraft"
    }

    #expect(result.commandName == "draftBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(draftFeature.outputs == [FeatureOutput(role: .body)])
    #expect(faceDraft.target.featureID == bodyFeatureID)
    #expect(Set(faceDraft.faces) == Set(targetEntries.prefix(2).map(\.stableReference)))
    #expect(faceDraft.neutralFace == neutralEntry.stableReference)
    #expect(body.kind == .solid)
    #expect(afterTopology.counts.faceCount == 6)
    #expect(draftFaces.count == 6)
    #expect(measurement.counts.solids == 1)
    #expect(measurement.solids.first?.featureID == draftFeatureID.description)
    #expect((measurement.solids.first?.volumeCubicMeters ?? 0.0) > 0.0)
    #expect(session.document.productMetadata.sceneNodes[draftNodeID]?.object?.geometryRole == .solid)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func draftBodyFacesRejectsObjectTargetsBeforeMutation() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(draftSceneNodeID(for: bodyFeatureID, in: session.document))

    do {
        _ = try session.execute(
            .draftBodyFaces(
                targets: [SelectionTarget(sceneNodeID: bodySceneNodeID)],
                neutralTarget: SelectionTarget(sceneNodeID: bodySceneNodeID),
                angle: .angle(10.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
        Issue.record("Draft Face should reject non-face object targets.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    #expect(session.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.last == bodyFeatureID)
    #expect(session.evaluationStatus == .valid)
}

private func draftSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}
