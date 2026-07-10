import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import RupaAgentTestFixtures
import SwiftCAD
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
            expectedGeneration: DocumentGeneration(1)
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
    let cylinderFaces = topologySummary.entries.filter { $0.kind == .face && $0.surfaceKind == "cylinder" }
    let circularEdges = topologySummary.entries.filter { $0.kind == .edge && $0.curveKind == "circle" }
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
    #expect(vertexComponentID.generatedTopologyPersistentName == vertexEntry.persistentName)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesCellUnionBooleanTopologyWithoutMutation() async throws {
    var document = DesignDocument.empty()
    let targetProfileID = try document.createRectangleSketchFromCorners(
        name: "Agent Cell Union Boolean Target Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-20.0, .millimeter),
            y: .length(-20.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(20.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let targetBodyID = try document.extrudeProfile(
        name: "Agent Cell Union Boolean Target",
        profile: ProfileReference(featureID: targetProfileID),
        distance: .length(10.0, .millimeter),
        direction: .normal
    )
    let toolProfileID = try document.createRectangleSketchFromCorners(
        name: "Agent Cell Union Boolean Tool Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(-5.0, .millimeter),
            y: .length(-5.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(25.0, .millimeter),
            y: .length(25.0, .millimeter)
        )
    )
    let pathID = try document.createLineSketch(
        name: "Agent Cell Union Boolean Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    _ = try document.createSweep(
        name: "Agent Cell Union Boolean Result Sweep",
        sections: [.profile(ProfileReference(featureID: toolProfileID))],
        path: SweepPathReference(featureID: pathID),
        targets: [SweepTargetReference(featureID: targetBodyID)],
        options: SweepOptions(booleanOperation: .difference)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .topologySummary(let topologySummary) = response else {
        Issue.record("Agent must return a topology summary.")
        return
    }
    let face = try #require(topologySummary.entries.first {
        $0.kind == .face
            && $0.generatedRole == "sideFace"
            && $0.subshapeRole == "cellUnion:component:0:face:maxX:x:maxX:y:minY-y1:z:minZ-maxZ"
    })
    let edge = try #require(topologySummary.entries.first {
        $0.kind == .edge
            && $0.generatedRole == "edge"
            && $0.subshapeRole == "cellUnion:component:0:zEdge:x:x1:y:y1:z:minZ-maxZ"
    })
    let vertex = try #require(topologySummary.entries.first {
        $0.kind == .vertex
            && $0.generatedRole == "vertex"
            && $0.subshapeRole == "cellUnion:component:0:vertex:x:x1:y:y1:z:maxZ"
    })
    #expect(face.selectionTarget() != nil)
    #expect(edge.selectionTarget() != nil)
    #expect(vertex.selectionTarget() != nil)
    #expect(topologySummary.counts.bodyCount == 1)
    #expect(topologySummary.counts.faceCount > 6)
    #expect(topologySummary.counts.edgeCount > 12)
    #expect(topologySummary.counts.vertexCount > 8)
    #expect(session.generation == DocumentGeneration(0))
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
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
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
@Test func agentSelectsSurfaceControlPointReferenceWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createPolySplineSurface(
        name: "Agent Reference Selection Surface",
        sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))
    let generation = session.generation
    let dirty = session.isDirty
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })

    let response = server.handle(
        .selectReferences(
            sessionID: sessionID,
            references: [controlPoint.selectionReference],
            expectedGeneration: generation
        )
    )

    guard case .selection(let result) = response else {
        Issue.record("Agent must return a selection result.")
        return
    }
    #expect(result.selectedTargets.isEmpty)
    #expect(result.selectedReferences == [controlPoint.selectionReference])
    #expect(session.selection.selectedReferences == [controlPoint.selectionReference])
    #expect(result.generation == generation)
    #expect(session.generation == generation)
    #expect(result.dirty == dirty)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentSavesOpenFileBackedSessionAndMarksClean() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let url = temporaryDirectory.appendingPathComponent("agent-save.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try DocumentFileService().load(from: url))
    _ = try session.execute(
        .renameDocument(name: "Saved Live"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: url, id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .save(let result) = response else {
        #expect(Bool(false))
        return
    }
    let loaded = try DocumentFileService().load(from: url)
    #expect(result.path == url.path)
    #expect(result.generation == DocumentGeneration(1))
    #expect(!result.dirty)
    #expect(!session.isDirty)
    #expect(loaded.cadDocument.metadata.name == "Saved Live")
}

@Test func agentSaveRejectsPathlessSession() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    server.register(session: EditorSession(document: .empty(named: "Pathless")), id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .commandInvalid)
    #expect(error.message.contains("file path"))
}

@MainActor
@Test func agentExportsOpenSessionWithoutMutation() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
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
            expectedGeneration: DocumentGeneration(1),
            options: ExportOptions(),
            dryRun: false
        )
    )

    guard case .export(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.format == .stl)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.byteCount == 84 + 12 * 50)
    #expect(session.generation == DocumentGeneration(1))
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func agentRejectsGenerationMismatchBeforeMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = try AutomationRunner().execute(.renameDocument(name: "Current"), in: session)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Rejected"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .documentGenerationMismatch)
    #expect(session.document.cadDocument.metadata.name == "Current")
    #expect(session.generation == DocumentGeneration(1))
}

@Test func agentReportsSessionNotFoundForUnknownSession() async throws {
    let server = AgentCommandController()
    let response = server.handle(
        .execute(
            sessionID: UUID(),
            command: .validateDocument,
            expectedGeneration: nil
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .sessionNotFound)
}

@MainActor
@Test func mainActorAgentBridgeRoutesSessionMutations() async throws {
    let bridge = MainActorAgentBridge()
    let sessionID = UUID()
    let session = EditorSession()
    bridge.register(session: session, id: sessionID)

    let response = bridge.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Main Actor Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Main Actor Live")
}
