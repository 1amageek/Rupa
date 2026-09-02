import Darwin
import Foundation
import RupaAgentIntegrationTestFixtures
import RupaAgentProtocol
import RupaAgentTestFixtures
import RupaAutomation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaAgent

@MainActor
@Test func agentSummarizesOpenSessionTopologyWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedCircle(
            name: "Agent Topology Cylinder",
            plane: .xy,
            center: .init(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(10.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )

    guard case .topologySummary(let topologySummary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(topologySummary.counts.bodyCount == 1)
    #expect(topologySummary.counts.faceCount == 6)
    #expect(topologySummary.counts.edgeCount == 12)
    #expect(topologySummary.counts.vertexCount == 8)
    let cylinderFaces = topologySummary.entries.filter {
        $0.kind == .face && $0.surfaceKind == "cylinder"
    }
    let circularEdges = topologySummary.entries.filter {
        $0.kind == .edge && $0.curveKind == "circle"
    }
    #expect(cylinderFaces.count == 4)
    #expect(circularEdges.count == 8)
    #expect(cylinderFaces.allSatisfy(hasExpectedAgentCylinderDefinition))
    #expect(circularEdges.allSatisfy(hasExpectedAgentCircularEdgeDefinition))
    #expect(topologySummary.entries.allSatisfy { $0.sceneNodeID != nil })
    let vertexEntry = try #require(topologySummary.entries.first { $0.kind == .vertex })
    let vertexTarget = try #require(vertexEntry.selectionTarget())
    guard case .vertex(let vertexComponentID) = vertexTarget.component else {
        Issue.record("Agent topology summary must expose vertex selection targets.")
        return
    }
    #expect(vertexComponentID.generatedTopologySubshapeID.map(GeneratedSubshapeIdentity.string(for:)) == vertexEntry.subshapeID)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

private func hasExpectedAgentCylinderDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard let radius = entry.surfaceRadius,
          let axis = entry.surfaceAxis else {
        return false
    }
    return abs(radius - 0.01) < 0.000_000_001
        && abs(axis.x) < 0.000_000_001
        && abs(axis.y) < 0.000_000_001
        && abs(abs(axis.z) - 1.0) < 0.000_000_001
}

private func hasExpectedAgentCircularEdgeDefinition(_ entry: TopologySummaryResult.Entry) -> Bool {
    guard let radius = entry.curveRadius,
          let center = entry.curveCenter,
          let normal = entry.curveNormal,
          let xAxis = entry.curveParameterXAxis,
          let yAxis = entry.curveParameterYAxis,
          let parameterRange = entry.edgeParameterRange else {
        return false
    }
    let span = abs(parameterRange.end - parameterRange.start)
    let xLength = sqrt(xAxis.x * xAxis.x + xAxis.y * xAxis.y + xAxis.z * xAxis.z)
    let yLength = sqrt(yAxis.x * yAxis.x + yAxis.y * yAxis.y + yAxis.z * yAxis.z)
    let xDotY = xAxis.x * yAxis.x + xAxis.y * yAxis.y + xAxis.z * yAxis.z
    let xDotNormal = xAxis.x * normal.x + xAxis.y * normal.y + xAxis.z * normal.z
    let yDotNormal = yAxis.x * normal.x + yAxis.y * normal.y + yAxis.z * normal.z
    return abs(radius - 0.01) < 0.000_000_001
        && abs(center.x) < 0.000_000_001
        && abs(center.y) < 0.000_000_001
        && abs(abs(normal.z) - 1.0) < 0.000_000_001
        && abs(xLength - 1.0) < 0.000_000_001
        && abs(yLength - 1.0) < 0.000_000_001
        && abs(xDotY) < 0.000_000_001
        && abs(xDotNormal) < 0.000_000_001
        && abs(yDotNormal) < 0.000_000_001
        && parameterRange.start.isFinite
        && parameterRange.end.isFinite
        && span > 0.0
        && span < Double.pi * 2.0
}

@MainActor
@Test func agentSelectsGeneratedTopologyVertexTargetWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let generation = session.generation
    let dirty = session.isDirty
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(sessionID: sessionID, expectedGeneration: generation)
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let vertexEntry = try #require(topology.entries.first { $0.kind == .vertex })
    let target = try #require(vertexEntry.selectionTarget())

    let response = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: generation
        )
    )
    guard case .selection(let result) = response else {
        Issue.record("Agent must return a selection result.")
        return
    }
    #expect(result.selectedTargets == [target])
    #expect(session.selection.selectedTargets == [target])
    #expect(result.generation == generation)
    #expect(session.generation == generation)
    #expect(result.dirty == dirty)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentSavesOpenFileBackedSessionAndMarksClean() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { removeTemporaryDirectory(temporaryDirectory) }
    let url = temporaryDirectory.appendingPathComponent("agent-save.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try DocumentFileService().load(from: url))
    _ = try session.execute(.renameDocument(name: "Saved Live"))
    server.register(session: session, path: url, id: sessionID)

    let response = server.handle(
        .save(sessionID: sessionID, expectedGeneration: session.generation)
    )
    guard case .save(let result) = response else {
        #expect(Bool(false))
        return
    }
    let loaded = try DocumentFileService().load(from: url)
    #expect(result.path == url.path)
    #expect(result.generation == session.generation)
    #expect(!result.dirty)
    #expect(!session.isDirty)
    #expect(loaded.cadDocument.metadata.name == "Saved Live")
}

@MainActor
@Test func agentExportsOpenSessionWithoutMutation() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { removeTemporaryDirectory(temporaryDirectory) }
    let outputURL = temporaryDirectory.appendingPathComponent("agent-box.stl")
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Export Box",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .export(
            sessionID: sessionID,
            outputPath: outputURL.path,
            expectedGeneration: session.generation,
            options: ExportOptions(),
            dryRun: false
        )
    )
    guard case .export(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.format == .stl)
    #expect(result.generation == session.generation)
    #expect(result.byteCount == 84 + 12 * 50)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func agentReportsSessionNotFoundForUnknownSession() async throws {
    let response = AgentCommandController().handle(
        .validateDocument(sessionID: UUID(), expectedGeneration: nil)
    )
    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .sessionNotFound)
}
