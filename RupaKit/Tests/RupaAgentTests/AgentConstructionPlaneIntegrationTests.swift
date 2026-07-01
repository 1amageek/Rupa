import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
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
                plane: .yz,
                activates: true
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

    let renamedSummaryResponse = server.handle(
        .constructionPlaneSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .constructionPlaneSummary(let renamedSummary) = renamedSummaryResponse else {
        #expect(Bool(false))
        return
    }
    let renamedEntry = try #require(renamedSummary.planes.first)
    #expect(renamedEntry.name == "Agent Renamed CPlane")
    let renamedSceneNodeID = try #require(renamedEntry.sceneNodeID)
    #expect(session.document.productMetadata.sceneNodes[renamedSceneNodeID]?.name == "Agent Renamed CPlane")
    let renamedTarget = try #require(renamedEntry.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [renamedTarget],
            expectedGeneration: DocumentGeneration(2)
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
            expectedGeneration: DocumentGeneration(2)
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
                viewNormal: Vector3D(x: 0.0, y: 3.0, z: 0.0),
                activates: true
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let source = try #require(session.activeConstructionPlane)
    #expect(result.commandName == "createViewAlignedConstructionPlane")
    #expect(result.didMutate)
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
    let topology = try TopologySummaryService().summarize(document: session.document)
    let faceTarget = try #require(topology.entries.first {
        $0.kind == .face && $0.center != nil && $0.normal != nil
    }?.selectionTarget())

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTarget(
                name: "Agent Face CPlane",
                target: faceTarget,
                activates: true
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
    #expect(entry.isActive)
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
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try agentParallelFaceTargets(in: topology)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Midplane",
                targets: targets,
                viewNormal: nil,
                activates: true
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
    #expect(entry.isActive)
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
    let topology = try TopologySummaryService().summarize(document: session.document)
    let targets = try agentTwoPointVertexTargets(in: topology, viewNormal: .unitZ)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createConstructionPlaneFromTargets(
                name: "Agent Two Point Plane",
                targets: targets,
                viewNormal: .unitZ,
                activates: true
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
    #expect(entry.isActive)
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
                viewNormal: .unitZ,
                activates: true
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
    #expect(entry.isActive)
    guard case .plane = entry.plane else {
        Issue.record("Two source point targets should create a custom construction plane.")
        return
    }
}
