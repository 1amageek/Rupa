import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentListsRegisteredSessions() async throws {
    let server = AgentCommandController(socketPath: "/tmp/rupa.sock")
    let sessionID = UUID()
    server.register(
        session: EditorSession(document: .empty(named: "Open Document")),
        path: URL(fileURLWithPath: "/tmp/open.swcad"),
        id: sessionID
    )

    let response = server.handle(.sessions)

    guard case .sessions(let sessions) = response else {
        #expect(Bool(false))
        return
    }
    #expect(sessions.count == 1)
    #expect(sessions[0].id == sessionID)
    #expect(sessions[0].displayName == "Open Document")
    #expect(sessions[0].generation == DocumentGeneration(0))
}

@Test func agentDispatchesCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Live")
}

@MainActor
@Test func agentProjectsGeneratedEdgeToConstructionPlaneThroughAutomation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Generated Edge Projection Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let supportFace = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.generatedRole == "startFace"
    })
    let supportDepth = try #require(supportFace.center?.z)
    let edge = try #require(topology.entries.first {
        $0.kind == .edge &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.curveKind == "line" &&
            agentTopologyPoint($0.start, isOnDepth: supportDepth) &&
            agentTopologyPoint($0.end, isOnDepth: supportDepth) &&
            $0.selectionTarget() != nil
    })
    let target = try #require(edge.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .projectSketchCurvesToConstructionPlane(
                targets: [target],
                plane: .xy,
                name: "Agent Projected Generated Edge"
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let projected = try #require(summary.entries.first {
        $0.sourceFeatureName == "Agent Projected Generated Edge"
    })

    #expect(result.commandName == "projectSketchCurvesToConstructionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(projected.entityKind == "line")
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentProjectsBodyOutlineToConstructionPlaneThroughAutomation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Body Outline Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .projectBodyOutlinesToConstructionPlane(
                targets: [SelectionTarget(sceneNodeID: bodyNodeID)],
                plane: .xy,
                name: "Agent Projected Body Outline"
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let projectedEntries = summary.entries.filter {
        $0.sourceFeatureName == "Agent Projected Body Outline"
    }

    #expect(result.commandName == "projectBodyOutlinesToConstructionPlane")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(projectedEntries.count == 4)
    #expect(projectedEntries.allSatisfy { $0.entityKind == "line" })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentProjectsCurvesToGeneratedFaceThroughAutomation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    let lineID = SketchEntityID()
    _ = try session.execute(
        .createSketch(
            name: "Agent Face Projection Source",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    lineID: .line(SketchLine(
                        start: SketchPoint(x: .length(1.0, .millimeter), y: .length(2.0, .millimeter)),
                        end: SketchPoint(x: .length(5.0, .millimeter), y: .length(4.0, .millimeter))
                    )),
                ]
            ),
            geometryRole: .curve
        )
    )
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Face Projection Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(20.0, .millimeter),
                y: .length(12.0, .millimeter)
            ),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(summary.entries.first { $0.entityID == lineID.description })
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(agentSceneNodeID(for: bodyFeatureID, in: session.document))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let face = try #require(topology.entries.first {
        $0.kind == .face &&
            $0.sceneNodeID == bodyNodeID.description &&
            $0.generatedRole == "endFace" &&
            $0.selectionTarget() != nil
    })
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .projectCurvesToGeneratedFace(
                targets: [try #require(sourceLine.selectionTarget())],
                face: try #require(face.selectionTarget()),
                name: "Agent Face Projected Line"
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let projected = try #require(after.entries.first {
        $0.sourceFeatureName == "Agent Face Projected Line"
    })

    #expect(result.commandName == "projectCurvesToGeneratedFace")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(projected.entityKind == "line")
    #expect(session.evaluationStatus == .valid)
}
