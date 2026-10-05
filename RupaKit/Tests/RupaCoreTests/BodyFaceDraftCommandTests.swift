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
    let measurement = try MeasurementService().measure(document: session.document, ruler: session.workspaceState.ruler)
    let draftFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == draftNodeID.description &&
            $0.generatedRole == "face"
    }

    #expect(result.commandName == "draftBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(draftFeature.outputs == [FeatureOutput(role: .body)])
    #expect(faceDraft.target.featureID == bodyFeatureID)
    #expect(faceDraft.faces.count == 1)
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
        .sorted { ($0.ordinal ?? -1) < ($1.ordinal ?? -1) }
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
    let measurement = try MeasurementService().measure(document: session.document, ruler: session.workspaceState.ruler)
    let draftFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == draftNodeID.description &&
            $0.generatedRole == "face"
    }

    #expect(result.commandName == "draftBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(draftFeature.outputs == [FeatureOutput(role: .body)])
    #expect(faceDraft.target.featureID == bodyFeatureID)
    #expect(faceDraft.faces.count == 2)
    #expect(Set(faceDraft.faces).count == 2)
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

/// Draft Face's Curve: a side face turned about its edge farthest from the neutral face, which
/// becomes a pivot of the kernel's curve method; the body stays one solid and, leaning in along
/// the pull, loses volume.
@MainActor
@Test func draftBodyFacesTakesTheCurveMethodsPivotEdge() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(draftSceneNodeID(for: bodyFeatureID, in: session.document))
    let before = try MeasurementService().measure(document: session.document, ruler: session.workspaceState.ruler)
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let bodyEntries = topology.entries.filter { $0.sceneNodeID == bodySceneNodeID.description }
    let side = try #require(bodyEntries.first { $0.kind == .face && $0.generatedRole == "sideFace" })
    let neutral = try #require(bodyEntries.first { $0.kind == .face && $0.generatedRole == "endFace" })
    let (sideOrigin, sideNormal) = (try #require(side.surfaceOrigin), try #require(side.surfaceNormal))
    let (neutralOrigin, neutralNormal) = (try #require(neutral.surfaceOrigin), try #require(neutral.surfaceNormal))
    func offset(_ p: TopologySummaryResult.Entry.Point, from o: TopologySummaryResult.Entry.Point, along n: TopologySummaryResult.Entry.Point) -> Double {
        (p.x - o.x) * n.x + (p.y - o.y) * n.y + (p.z - o.z) * n.z
    }
    // The side face's edges level with the neutral face; the pivot is the one farthest from it.
    let level = bodyEntries.filter { entry in
        guard entry.kind == .edge, let start = entry.start, let end = entry.end else { return false }
        return abs(offset(start, from: sideOrigin, along: sideNormal)) < 1e-9 && abs(offset(end, from: sideOrigin, along: sideNormal)) < 1e-9
            && abs(offset(start, from: neutralOrigin, along: neutralNormal) - offset(end, from: neutralOrigin, along: neutralNormal)) < 1e-9
    }
    let pivot = try #require(level.max { a, b in
        abs(offset(a.start!, from: neutralOrigin, along: neutralNormal)) < abs(offset(b.start!, from: neutralOrigin, along: neutralNormal))
    })

    let result = try session.execute(
        .draftBodyFaces(
            targets: [try #require(side.selectionTarget())],
            neutralTarget: try #require(neutral.selectionTarget()),
            angle: .angle(10.0, .degree),
            method: .curve(pivots: [try #require(pivot.selectionTarget())])
        ),
        expectedGeneration: DocumentGeneration(1)
    )

    let draftFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let draftFeature = try #require(session.document.cadDocument.designGraph.nodes[draftFeatureID])
    guard case let .faceDraft(faceDraft) = draftFeature.operation, case let .curve(pivots) = faceDraft.method else {
        Issue.record("Draft Face's Curve should create a FaceDraft feature with the curve method.")
        return
    }
    let after = try MeasurementService().measure(document: session.document, ruler: session.workspaceState.ruler)
    #expect(result.didMutate)
    #expect(pivots.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(after.counts.solids == 1)
    #expect((after.solids.first?.volumeCubicMeters ?? 0) < (before.solids.first?.volumeCubicMeters ?? 0))
}

private func draftSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}
