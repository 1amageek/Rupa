import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@Test func agentCreatesReadsAndActivatesConstructionPlanes() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlane(
                name: "Agent CPlane",
                plane: .yz
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        #expect(Bool(false))
        return
    }
    #expect(createResult.commandName == "createConstructionPlane")
    #expect(createResult.didMutate)
    #expect(createResult.effect == .sourceMutation)
    let createdPlaneID = try #require(createResult.createdConstructionPlaneID)

    let activateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setActiveConstructionPlane(id: createdPlaneID),
            expectedGeneration: createResult.generation,
            expectedWorkspaceRevision: WorkspaceRevision(0)
        )
    )
    guard case .command(let activateResult) = activateResponse else {
        #expect(Bool(false))
        return
    }
    #expect(activateResult.effect == .workspaceMutation)
    #expect(activateResult.generation == createResult.generation)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first)
    #expect(entry.name == "Agent CPlane")
    #expect(entry.plane == .yz)
    #expect(entry.isActive)
    #expect(entry.id == createdPlaneID)
    #expect(summary.activePlaneID == entry.id)
    #expect(entry.sceneNodeID != nil)

    let renameResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameConstructionPlane(
                id: entry.id,
                name: "Agent Renamed CPlane"
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let renameResult) = renameResponse else {
        #expect(Bool(false))
        return
    }
    #expect(renameResult.commandName == "renameConstructionPlane")
    #expect(renameResult.didMutate)

    let editedPlane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 0.010, y: 0.020, z: 0.030),
            normal: .unitZ
        )
    )
    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setConstructionPlane(
                id: entry.id,
                plane: editedPlane
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let editResult) = editResponse else {
        #expect(Bool(false))
        return
    }
    #expect(editResult.commandName == "setConstructionPlane")
    #expect(editResult.didMutate)

    let renamedSummaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .constructionPlaneSummary(let renamedSummary) = renamedSummaryResponse else {
        #expect(Bool(false))
        return
    }
    let renamedEntry = try #require(renamedSummary.planes.first)
    #expect(renamedEntry.name == "Agent Renamed CPlane")
    #expect(renamedEntry.plane == editedPlane)
    let renamedSceneNodeID = try #require(renamedEntry.sceneNodeID)
    #expect(session.document.productMetadata.sceneNodes[renamedSceneNodeID]?.name == "Agent Renamed CPlane")
    let renamedTarget = try #require(renamedEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [renamedTarget],
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selection(let selectionResult) = selectionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(selectionResult.selectedTargets == [renamedTarget])
    #expect(session.selection.selectedTargets == [renamedTarget])

    let clearResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setActiveConstructionPlane(id: nil),
            expectedGeneration: DocumentGeneration(3),
            expectedWorkspaceRevision: WorkspaceRevision(1)
        )
    )
    guard case .command(let clearResult) = clearResponse else {
        #expect(Bool(false))
        return
    }
    #expect(clearResult.commandName == "setActiveConstructionPlane")
    #expect(clearResult.didMutate)
    #expect(session.activeConstructionPlane == nil)
}

@Test func agentCreatesSketchOnReferencedConstructionPlane() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createPlaneResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlane(
                name: "Agent Referenced Sketch Plane",
                plane: .yz
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createPlaneResult) = createPlaneResponse else {
        #expect(Bool(false))
        return
    }
    #expect(createPlaneResult.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: createPlaneResult.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let plane = try #require(summary.planes.first { $0.name == "Agent Referenced Sketch Plane" })

    let sketchResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLineSketch(
                name: "Agent Referenced Plane Line",
                plane: .constructionPlane(plane.id),
                start: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                end: SketchPoint(
                    x: .length(10.0, .millimeter),
                    y: .length(5.0, .millimeter)
                )
            ),
            expectedGeneration: createPlaneResult.generation
        )
    )
    guard case .command(let sketchResult) = sketchResponse else {
        #expect(Bool(false))
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Agent construction-plane-referenced sketch command must create a sketch feature.")
        return
    }

    #expect(sketchResult.commandName == "createLineSketch")
    #expect(sketchResult.didMutate)
    #expect(sketchResult.generation == DocumentGeneration(2))
    #expect(session.activeConstructionPlane == nil)
    #expect(sketch.plane == .yz)
}

@Test func agentRejectsUnresolvedConstructionPlaneSketchReferenceBeforeMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    let missingID = ConstructionPlaneSourceID()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createLineSketch(
                name: "Agent Missing Plane Line",
                plane: .constructionPlane(missingID),
                start: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                end: SketchPoint(
                    x: .length(10.0, .millimeter),
                    y: .length(5.0, .millimeter)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }

    #expect(error.code == .referenceUnresolved)
    #expect(error.message.contains("construction plane source"))
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@Test func agentCreatesViewAlignedConstructionPlane() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createViewAlignedConstructionPlane(
                name: "Agent View Plane",
                origin: Point3D(x: 0.010, y: 0.020, z: 0.030),
                viewNormal: Vector3D(x: 0.0, y: 3.0, z: 0.0)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sourceID = try #require(result.createdConstructionPlaneID)
    let source = try #require(session.document.productMetadata.constructionPlanes[sourceID])
    #expect(result.commandName == "createViewAlignedConstructionPlane")
    #expect(result.didMutate)
    #expect(session.activeConstructionPlane == nil)
    #expect(source.name == "Agent View Plane")
    guard case .plane(let plane) = source.plane else {
        Issue.record("Agent view-aligned construction plane should create a custom plane.")
        return
    }
    #expect(plane.normal == .unitY)
}

@Test func agentCreatesConstructionPlaneFromGeneratedFaceTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let faceTarget = try #require(topology.entries.first {
        $0.kind == .face && $0.center != nil && $0.normal != nil
    }?.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTarget(
                name: "Agent Face CPlane",
                target: faceTarget
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTarget")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Face CPlane" })
    #expect(entry.id == result.createdConstructionPlaneID)
    #expect(!entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Generated face target should create a custom construction plane.")
        return
    }
}

@Test func agentCreatesMidplaneConstructionPlaneFromGeneratedFaceTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let targets = try agentParallelFaceTargets(in: topology)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Midplane",
                targets: targets,
                viewNormal: nil
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Midplane" })
    #expect(entry.id == result.createdConstructionPlaneID)
    #expect(!entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Parallel generated face targets should create a custom midplane.")
        return
    }
}

@Test func agentCreatesTwoPointConstructionPlaneFromGeneratedVertexTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let targets = try agentTwoPointVertexTargets(in: topology, viewNormal: .unitZ)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Two Point Plane",
                targets: targets,
                viewNormal: .unitZ
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Two Point Plane" })
    #expect(entry.id == result.createdConstructionPlaneID)
    #expect(!entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Two generated vertex targets should create a custom construction plane.")
        return
    }
}

@Test func agentCreatesTwoPointConstructionPlaneFromSourcePointTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSourcePointSession()
    let session = setup.session
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Source Point Plane",
                targets: setup.targets,
                viewNormal: .unitZ
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createConstructionPlaneFromTargets")
    #expect(result.didMutate)

    let summaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: result.generation
        )
    )
    guard case .constructionPlaneSummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let entry = try #require(summary.planes.first { $0.name == "Agent Source Point Plane" })
    #expect(entry.id == result.createdConstructionPlaneID)
    #expect(!entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Two source point targets should create a custom construction plane.")
        return
    }
}
