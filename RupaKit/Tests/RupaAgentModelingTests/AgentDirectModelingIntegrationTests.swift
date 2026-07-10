import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@Test func agentDispatchesFaceOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: SelectionTarget(sceneNodeID: bodyNodeID, component: .face(.bodyFaceTop)),
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyFaceOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "sideFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: target,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedProfileEdgeMoveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let circularEdge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle"
    })
    let target = try #require(circularEdge.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyEdge(
                target: target,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(-1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(result.commandName == "moveBodyEdge")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedArcEdgeMoveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let filletResult) = filletResponse else {
        Issue.record("Agent must return a fillet command result.")
        return
    }

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let arcEdge = try #require(topology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            nearlyEqualAgent(radius, 0.001)
    })
    let target = try #require(arcEdge.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyEdge(
                target: target,
                deltaX: .length(-1.0, .millimeter),
                deltaY: .length(-1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let movedArcEdge = try #require(afterTopology.entries.first {
        guard let radius = $0.curveRadius else {
            return false
        }
        return $0.kind == .edge &&
            $0.generatedRole == "edge" &&
            $0.curveKind == "circle" &&
            nearlyEqualAgent(radius, 0.002)
    })

    #expect(filletResult.commandName == "filletBodyEdges")
    #expect(filletResult.didMutate)
    #expect(filletResult.generation == DocumentGeneration(2))
    #expect(result.commandName == "moveBodyEdge")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(movedArcEdge.selectionTarget() != nil)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesFaceKnifeCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createFaceKnife(
                name: "Agent Face Knife",
                target: target,
                loop: [
                    Point3D(x: -0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: -0.002, z: 0.0),
                    Point3D(x: 0.004, y: 0.002, z: 0.0),
                    Point3D(x: -0.004, y: 0.002, z: 0.0),
                ]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let faceKnifeFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let faceKnifeSceneNodeID = try #require(agentSceneNodeID(for: faceKnifeFeatureID, in: session.document))
    let feature = try #require(session.document.cadDocument.designGraph.nodes[faceKnifeFeatureID])
    guard case .faceKnife = feature.operation else {
        Issue.record("Agent Face Knife command must create a FaceKnife feature.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let faceKnifeFaces = afterTopology.entries.filter {
        $0.kind == .face && $0.sceneNodeID == faceKnifeSceneNodeID.description
    }

    #expect(result.commandName == "createFaceKnife")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(faceKnifeFaces.count == 7)
    #expect(faceKnifeFaces.contains {
        $0.generatedRole == "faceKnife" && $0.subshapeRole == "centerFace"
    })
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyFaceDeleteCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .deleteBodyFaces(targets: [target]),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let deleteFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let deleteSceneNodeID = try #require(agentSceneNodeID(for: deleteFeatureID, in: session.document))
    let feature = try #require(session.document.cadDocument.designGraph.nodes[deleteFeatureID])
    guard case .faceDelete = feature.operation else {
        Issue.record("Agent Delete Face command must create a FaceDelete feature.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    let carriedFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == deleteSceneNodeID.description &&
            $0.generatedRole == "faceDelete" &&
            $0.subshapeRole == "carriedFace"
    }

    #expect(result.commandName == "deleteBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(body.kind == .sheet)
    #expect(afterTopology.counts.faceCount == 5)
    #expect(afterTopology.entries.contains { $0.persistentName == faceEntry.persistentName } == false)
    #expect(carriedFaces.count == 5)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyFaceDraftCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let targetEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "sideFace"
    })
    let neutralEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let target = try #require(targetEntry.selectionTarget())
    let neutralTarget = try #require(neutralEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .draftBodyFaces(
                targets: [target],
                neutralTarget: neutralTarget,
                angle: .angle(8.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let draftFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let draftSceneNodeID = try #require(agentSceneNodeID(for: draftFeatureID, in: session.document))
    let feature = try #require(session.document.cadDocument.designGraph.nodes[draftFeatureID])
    guard case .faceDraft = feature.operation else {
        Issue.record("Agent Draft Face command must create a FaceDraft feature.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    let draftFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == draftSceneNodeID.description &&
            $0.generatedRole == "faceDraft"
    }

    #expect(result.commandName == "draftBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(body.kind == .solid)
    #expect(afterTopology.counts.faceCount == 6)
    #expect(draftFaces.count == 6)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesMultipleGeneratedTopologyFaceDraftTargetsThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let targetEntries = topology.entries
        .filter { entry in
            entry.kind == .face && entry.generatedRole == "sideFace"
        }
        .sorted { ($0.index ?? -1) < ($1.index ?? -1) }
    let firstTarget = try #require(targetEntries.first?.selectionTarget())
    let secondTarget = try #require(targetEntries.dropFirst().first?.selectionTarget())
    let neutralEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let neutralTarget = try #require(neutralEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .draftBodyFaces(
                targets: [firstTarget, secondTarget],
                neutralTarget: neutralTarget,
                angle: .angle(8.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let draftFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let draftSceneNodeID = try #require(agentSceneNodeID(for: draftFeatureID, in: session.document))
    let feature = try #require(session.document.cadDocument.designGraph.nodes[draftFeatureID])
    guard case let .faceDraft(faceDraft) = feature.operation else {
        Issue.record("Agent Draft Face command must create a FaceDraft feature.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let evaluation = try #require(session.currentEvaluationCache?.evaluatedDocument)
    let body = try #require(evaluation.brep.bodies.values.first)
    let draftFaces = afterTopology.entries.filter {
        $0.kind == .face &&
            $0.sceneNodeID == draftSceneNodeID.description &&
            $0.generatedRole == "faceDraft"
    }

    #expect(result.commandName == "draftBodyFaces")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(faceDraft.facePersistentNames.count == 2)
    #expect(Set(faceDraft.facePersistentNames).count == 2)
    #expect(body.kind == .solid)
    #expect(afterTopology.counts.faceCount == 6)
    #expect(draftFaces.count == 6)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyEdgeOffsetCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.gapFill == .linear)
    #expect(afterTopology.counts.faceCount == 7)
    #expect(afterTopology.counts.edgeCount == 15)
    #expect(afterTopology.counts.vertexCount == 10)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesOffsetEdgeUsingSelectedSupportFaceContext() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [supportFaceTarget, edgeTarget],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selectionResult) = selectionResponse else {
        Issue.record("Agent must return a selection result before Offset Edge.")
        return
    }
    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .linear),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature from selection context.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(selectionResult.selectedTargets == [supportFaceTarget, edgeTarget])
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.gapFill == .linear)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesOffsetEdgeUsingSingleSelectedCapEdgeContext() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [edgeTarget],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selectionResult) = selectionResponse else {
        Issue.record("Agent must return a single edge selection result before Offset Edge.")
        return
    }
    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .linear),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent Offset Curve edge target must create an EdgeOffset feature from cap edge context.")
        return
    }
    let afterTopology = try TopologySnapshotService().snapshot(document: session.document)
    let generatedOffsetEdges = afterTopology.entries.filter {
        $0.kind == .edge &&
            $0.sourceFeatureID == offsetFeatureID.description &&
            $0.generatedRole == "edgeOffset" &&
            $0.subshapeRole == "offsetEdge"
    }

    #expect(selectionResult.selectedTargets == [edgeTarget])
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(edgeOffset.target == EdgeOffsetTargetReference(featureID: bodyFeatureID))
    #expect(edgeOffset.supportFacePersistentName.components == [
        .feature(bodyFeatureID),
        .generated(GeneratedSubshapeRole.startFace.rawValue),
    ])
    #expect(edgeOffset.gapFill == .linear)
    #expect(generatedOffsetEdges.count == 1)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentOffsetsGeneratedCylinderSideFaceThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let beforeRadius = try agentCylinderRadius(forBody: bodyFeatureID, in: session.document)
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.surfaceKind == "cylinder"
    })
    let target = try #require(faceEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetBodyFace(
                target: target,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "offsetBodyFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(nearlyEqualAgent(try agentCylinderRadius(forBody: bodyFeatureID, in: session.document), beforeRadius + 0.001))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesEdgeChamferCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeLeftTop)),
                ],
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "chamferBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesEdgeFilletCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightBottom)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyEdgeFilletCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsLineArcProfileCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcExtrudedSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 2.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(100.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsArcArcProfileCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentArcArcExtrudedSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 0.0, y: 0.0)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(100.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "filletBodyEdges")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsGeneratedEdgeAfterPriorChamferThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let chamferResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let chamferResult) = chamferResponse else {
        #expect(Bool(false))
        return
    }
    #expect(chamferResult.commandName == "chamferBodyEdges")
    #expect(chamferResult.didMutate)
    #expect(chamferResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first(where: isAgentVerticalGeneratedEdge))
    let target = try #require(edgeEntry.selectionTarget())

    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(0.25, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let filletResult) = filletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(filletResult.commandName == "filletBodyEdges")
    #expect(filletResult.didMutate)
    #expect(filletResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentFilletsSharpGeneratedEdgeAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let firstFilletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let firstFilletResult) = firstFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(firstFilletResult.commandName == "filletBodyEdges")
    #expect(firstFilletResult.didMutate)
    #expect(firstFilletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: -0.020, y: -0.010)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let secondFilletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [target],
                radius: .length(0.5, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let secondFilletResult) = secondFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(secondFilletResult.commandName == "filletBodyEdges")
    #expect(secondFilletResult.didMutate)
    #expect(secondFilletResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentChamfersArcAdjacentGeneratedEdgeAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let firstFilletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let firstFilletResult) = firstFilletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(firstFilletResult.commandName == "filletBodyEdges")
    #expect(firstFilletResult.didMutate)
    #expect(firstFilletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let edgeEntry = try #require(topology.entries.first {
        isAgentVerticalGeneratedEdge($0, x: 0.020, y: 0.009)
    })
    let target = try #require(edgeEntry.selectionTarget())

    let chamferResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .chamferBodyEdges(
                targets: [target],
                distance: .length(0.25, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let chamferResult) = chamferResponse else {
        #expect(Bool(false))
        return
    }
    #expect(chamferResult.commandName == "chamferBodyEdges")
    #expect(chamferResult.didMutate)
    #expect(chamferResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesGeneratedTopologyVertexMoveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(vertexEntry.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyVertex(
                target: target,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(result.commandName == "moveBodyVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentMovesSharpGeneratedVertexAfterPriorFilletThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let filletResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .filletBodyEdges(
                targets: [
                    SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop)),
                ],
                radius: .length(1.0, .millimeter),
                segmentCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let filletResult) = filletResponse else {
        #expect(Bool(false))
        return
    }
    #expect(filletResult.commandName == "filletBodyEdges")
    #expect(filletResult.didMutate)
    #expect(filletResult.generation == DocumentGeneration(2))

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first {
        isAgentGeneratedVertex($0, x: -0.020, y: -0.010)
    })
    let target = try #require(vertexEntry.selectionTarget())

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveBodyVertex(
                target: target,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.5, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(moveResult.commandName == "moveBodyVertex")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesCornerFootprintModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangleFromCorners(
                name: "Agent Footprint Box",
                plane: .xy,
                firstCorner: SketchPoint(
                    x: .length(1.0, .millimeter),
                    y: .length(2.0, .millimeter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(5.0, .millimeter),
                    y: .length(8.0, .millimeter)
                ),
                depth: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}
