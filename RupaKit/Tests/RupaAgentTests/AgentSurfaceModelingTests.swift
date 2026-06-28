import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentDispatchesPolySplineCommandAndExposesBSplineTopology() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent PolySpline",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createPolySplineSurface")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)

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
    #expect(topology.counts.bodyCount == 1)
    #expect(topology.counts.faceCount == 1)
    #expect(topology.counts.edgeCount == 4)
    #expect(topology.counts.vertexCount == 4)
    let face = try #require(topology.entries.first {
        $0.kind == .face
            && $0.surfaceKind == "bSpline"
            && $0.generatedRole == "polySpline"
            && $0.subshapeRole == "patch:0:face"
    })
    #expect(face.surfaceUDegree == 3)
    #expect(face.surfaceVDegree == 3)
    #expect(face.surfaceUControlPointCount == 4)
    #expect(face.surfaceVControlPointCount == 4)
    #expect(face.selectionTarget() != nil)
    #expect(topology.entries.contains {
        $0.kind == .edge
            && $0.subshapeRole == "patch:0:edge:uMax"
            && $0.selectionTarget() != nil
    })
    #expect(topology.entries.contains {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMax"
            && $0.selectionTarget() != nil
    })
}

@MainActor
@Test func agentMovesPolySplineSurfaceVertexThroughGeneratedTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Editable Surface",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

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
    let vertexEntry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMax"
    })
    let target = try #require(vertexEntry.selectionTarget())

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .movePolySplineSurfaceVertex(
                target: target,
                deltaX: .length(0.0, .millimeter),
                deltaY: .length(0.0, .millimeter),
                deltaZ: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move a PolySpline surface vertex.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    #expect(moveResult.commandName == "movePolySplineSurfaceVertex")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[2].z - 0.005) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentMovesSurfaceControlPointThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Reference Move",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlVertex = try #require(patch.controlVertices.first { $0.role == "uMax:vMax" })

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSurfaceControlPoint(
                target: controlVertex.selectionReference,
                deltaX: .length(0.0, .millimeter),
                deltaY: .length(0.0, .millimeter),
                deltaZ: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move a surface control point from a surface source reference.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    #expect(moveResult.commandName == "moveSurfaceControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[2].z - 0.005) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentMovesInteriorSurfaceControlPointThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Interior Surface Reference Move",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSurfaceControlPoint(
                target: controlPoint.selectionReference,
                deltaX: .length(0.0, .millimeter),
                deltaY: .length(0.0, .millimeter),
                deltaZ: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move an interior surface control point from a surface source reference.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    let override = try #require(polySpline.controlPointOverrides.first)
    #expect(moveResult.commandName == "moveSurfaceControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(override.uIndex == 1)
    #expect(override.vIndex == 1)
    #expect(abs(override.point.z - (controlPoint.point.z + 0.001)) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsInteriorSurfaceControlPointWeightThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Weighted Interior Surface Reference",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let controlPoint = try #require(
        summary.sources.first?.patches.first?.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )

    let weightResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceControlPointWeight(
                target: controlPoint.selectionReference,
                weight: .scalar(2.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let weightResult) = weightResponse else {
        Issue.record("Agent must set an interior surface control point weight from a surface source reference.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    let override = try #require(polySpline.controlPointOverrides.first)
    #expect(weightResult.commandName == "setSurfaceControlPointWeight")
    #expect(weightResult.didMutate)
    #expect(weightResult.generation == DocumentGeneration(2))
    #expect(override.uIndex == 1)
    #expect(override.vIndex == 1)
    #expect(override.weight == 2.5)
    #expect(session.evaluationStatus == .valid)

    let updatedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let updatedSummary) = updatedSummaryResponse else {
        Issue.record("Agent must return an updated weighted surface source summary.")
        return
    }
    let updatedPatch = try #require(updatedSummary.sources.first?.patches.first)
    let updatedControlPoint = try #require(
        updatedPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    #expect(updatedPatch.basis.isRational)
    #expect(updatedControlPoint.weight == 2.5)
}

@MainActor
@Test func agentSlidesPolySplineSurfaceVerticesThroughGeneratedTargets() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Slide Surface",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

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
    let vertexEntry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMin"
    })
    let target = try #require(vertexEntry.selectionTarget())

    let slideResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slidePolySplineSurfaceVertices(
                targets: [target],
                direction: .positiveV,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let slideResult) = slideResponse else {
        Issue.record("Agent must slide PolySpline surface vertices.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    let length = sqrt((0.02 * 0.02) + (0.004 * 0.004))
    #expect(slideResult.commandName == "slidePolySplineSurfaceVertices")
    #expect(slideResult.didMutate)
    #expect(slideResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[1].y - (0.02 / length * 0.001)) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].z - (0.004 / length * 0.001)) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSlidesSurfaceControlPointsThroughSurfaceSourceReferences() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Reference Slide",
                sourceMesh: agentPolySplineQuadMesh(),
                options: PolySplineOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a PolySpline surface.")
        return
    }
    #expect(createResult.didMutate)

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlVertex = try #require(patch.controlVertices.first { $0.role == "uMax:vMin" })

    let slideResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slideSurfaceControlPoints(
                targets: [controlVertex.selectionReference],
                direction: .positiveV,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let slideResult) = slideResponse else {
        Issue.record("Agent must slide surface control points from surface source references.")
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Agent must keep a PolySpline feature.")
        return
    }
    let length = sqrt((0.02 * 0.02) + (0.004 * 0.004))
    #expect(slideResult.commandName == "slideSurfaceControlPoints")
    #expect(slideResult.didMutate)
    #expect(slideResult.generation == DocumentGeneration(2))
    #expect(abs(polySpline.sourceMesh.positions[1].y - (0.02 / length * 0.001)) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].z - (0.004 / length * 0.001)) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentPreflightsPolySplineMeshWithoutMutatingDocument() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .polySplineMeshAnalysis(
            sessionID: sessionID,
            sourceMesh: agentPolySplineQuadMesh(),
            options: PolySplineOptions(roundedCorners: true),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .polySplineMeshAnalysis(let result) = response else {
        Issue.record("Agent must return PolySpline mesh analysis.")
        return
    }
    #expect(!result.isSupported)
    #expect(result.candidateKind == .singleQuad)
    #expect(result.supportedPatchCount == 1)
    #expect(result.candidatePatchCount == 1)
    #expect(result.patchGraph?.candidates.count == 1)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0])
    #expect(result.errors.contains { $0.code == .unsupportedRoundedCorners })
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func agentPreflightsPolySplinePatchGraphWithoutMutatingDocument() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .polySplineMeshAnalysis(
            sessionID: sessionID,
            sourceMesh: agentPolySplinePatchNetworkMesh(),
            options: PolySplineOptions(),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .polySplineMeshAnalysis(let result) = response else {
        Issue.record("Agent must return PolySpline mesh analysis.")
        return
    }
    #expect(!result.isSupported)
    #expect(result.candidateKind == .quadPatchGraph)
    #expect(result.supportedPatchCount == 0)
    #expect(result.candidatePatchCount == 3)
    #expect(result.patchGraph?.ambiguousTriangleIndices == [0, 3])
    #expect(result.patchGraph?.partition?.isComplete == true)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0, 2])
    #expect(result.patchGraph?.partition?.rejectedCandidateIDs == [1])
    let adjacency = try #require(result.patchGraph?.selectedAdjacencies.first)
    #expect(result.patchGraph?.selectedAdjacencies.count == 1)
    #expect(adjacency.firstCandidateID == 0)
    #expect(adjacency.secondCandidateID == 2)
    #expect(adjacency.sharedVertexIndices == [1, 4])
    #expect(adjacency.continuityLevel == .positional)
    #expect(adjacency.requiresCurvatureContinuitySolve)
    #expect(result.diagnostics.contains { $0.code == .patchGraphIdentified })
    #expect(result.diagnostics.contains { $0.code == .patchGraphPartitioned })
    #expect(result.diagnostics.contains { $0.code == .patchAdjacencyIdentified })
    #expect(result.diagnostics.contains { $0.code == .patchTangentPlaneDiscontinuity })
    #expect(result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
    #expect(result.errors.contains { $0.code == .unsupportedPatchNetwork })
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@Test func agentPreflightsPlanarUnmergedPolySplinePatchGraphWithoutMutatingDocument() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .polySplineMeshAnalysis(
            sessionID: sessionID,
            sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
            options: PolySplineOptions(mergePatches: false),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .polySplineMeshAnalysis(let result) = response else {
        Issue.record("Agent must return PolySpline mesh analysis.")
        return
    }
    #expect(result.isSupported)
    #expect(result.candidateKind == .quadPatchGraph)
    #expect(result.supportedPatchCount == 2)
    #expect(result.candidatePatchCount == 3)
    #expect(result.patchGraph?.partition?.isComplete == true)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0, 2])
    #expect(result.patchGraph?.selectedAdjacencies.count == 1)
    #expect(result.patchGraph?.selectedAdjacencies.first?.continuityLevel == .tangentPlane)
    #expect(result.patchGraph?.selectedAdjacencies.first?.requiresCurvatureContinuitySolve == false)
    #expect(result.diagnostics.contains { $0.code == .planarPatchNetworkSupported })
    #expect(!result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
    #expect(result.errors.isEmpty)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test func agentReportsPolySplineSurfaceSourceSummaryWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Source Summary",
                sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
                options: PolySplineOptions(mergePatches: false)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a planar PolySpline patch network.")
        return
    }
    #expect(createResult.didMutate)
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )

    guard case .surfaceSourceSummary(let summary) = response else {
        Issue.record("Agent must return a surface source summary.")
        return
    }
    #expect(summary.counts.sourceCount == 1)
    #expect(summary.counts.patchCount == 2)
    #expect(summary.counts.controlVertexCount == 8)
    #expect(summary.counts.trimLoopCount == 2)
    #expect(summary.counts.adjacencyCount == 1)
    let source = try #require(summary.sources.first)
    #expect(source.kind == "polySpline")
    #expect(source.support.isSupported)
    #expect(source.support.candidateKind == "quadPatchGraph")
    #expect(source.patches.map(\.patchID) == [0, 2])
    let patch = try #require(source.patches.first)
    #expect(patch.facePersistentName?.contains("subshape:patch:0:face") == true)
    #expect(patch.faceSelectionComponentID?.hasPrefix(SelectionComponentID.generatedTopologyPrefix) == true)
    #expect(patch.basis.kind == "cubicBezierBSpline")
    #expect(patch.controlVertices.count == 4)
    #expect(patch.controlVertices.allSatisfy {
        $0.selectionComponentID.hasPrefix(SelectionComponentID.generatedTopologyPrefix)
    })
    let firstControlVertex = try #require(patch.controlVertices.first)
    let measurementResponse = server.handle(
        .selectionMeasurement(
            sessionID: sessionID,
            query: CADAgentMeasurementQuery(kind: .point, first: firstControlVertex.selectionReference),
            expectedGeneration: generation
        )
    )
    guard case .selectionMeasurement(.point(let measuredPoint)) = measurementResponse else {
        Issue.record("Agent must measure a discovered surface control-point selection reference.")
        return
    }
    #expect(abs(measuredPoint.point.x - firstControlVertex.point.x) <= 1.0e-12)
    #expect(abs(measuredPoint.point.y - firstControlVertex.point.y) <= 1.0e-12)
    #expect(abs(measuredPoint.point.z - firstControlVertex.point.z) <= 1.0e-12)
    #expect(patch.trimLoops.first?.edgePersistentNames.count == 4)
    #expect(patch.trimLoops.first?.selectionReferences.count == 4)
    let adjacency = try #require(source.adjacencies.first)
    #expect(adjacency.continuityLevel == "tangentPlane")
    #expect(adjacency.requiresCurvatureContinuitySolve == false)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentReportsPlanarPolySplineSurfaceAnalysisWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Analysis",
                sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
                options: PolySplineOptions(mergePatches: false)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a planar PolySpline patch network.")
        return
    }
    #expect(createResult.didMutate)
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .surfaceAnalysis(
            sessionID: sessionID,
            options: SurfaceAnalysisOptions(sampleDensity: .high),
            expectedGeneration: generation
        )
    )

    guard case .surfaceAnalysis(let analysis) = response else {
        Issue.record("Agent must return a surface analysis result.")
        return
    }
    #expect(analysis.counts.bSplineFaceCount == 2)
    #expect(analysis.counts.sampleCount == 162)
    #expect(analysis.counts.uCurvatureCombCount == 162)
    #expect(analysis.counts.vCurvatureCombCount == 162)
    #expect(analysis.counts.trimBoundaryCount == 2)
    #expect(analysis.counts.innerTrimBoundaryCount == 0)
    #expect(analysis.counts.openTrimBoundaryCount == 0)
    #expect(analysis.counts.trimBoundaryEdgeCount == 8)
    let face = try #require(analysis.faces.first)
    #expect(face.facePersistentNames.contains { $0.contains("subshape:patch") })
    #expect(face.edgePersistentNames.contains { $0.contains("subshape:patch") })
    let trimBoundary = try #require(face.trimBoundaries.first)
    #expect(trimBoundary.role == .outer)
    #expect(trimBoundary.edgeCount == 4)
    #expect(trimBoundary.vertexCount == 4)
    #expect(trimBoundary.points.count == 4)
    #expect(trimBoundary.isClosed)
    #expect(trimBoundary.estimatedLength > 0.0)
    #expect(face.maxUNormalChangePerLength <= 1.0e-8)
    #expect(face.maxVNormalChangePerLength <= 1.0e-8)
    #expect(face.maxAbsUNormalCurvature <= 1.0e-8)
    #expect(face.maxAbsVNormalCurvature <= 1.0e-8)
    #expect(face.maxAbsPrincipalCurvature <= 1.0e-8)
    #expect(face.maxAbsGaussianCurvature <= 1.0e-8)
    let sample = try #require(face.samples.first)
    #expect(abs(surfaceVectorLength(sample.minimumPrincipalDirection) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorLength(sample.maximumPrincipalDirection) - 1.0) <= 1.0e-8)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}

@MainActor
@Test func agentReportsPlanarPolySplineSurfaceContinuityWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Planar Patch Network",
                sourceMesh: agentPolySplinePatchNetworkMesh(centerZ: 0.0),
                options: PolySplineOptions(mergePatches: false)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a planar PolySpline patch network.")
        return
    }
    #expect(createResult.didMutate)
    let generation = session.generation
    let dirty = session.isDirty

    let response = server.handle(
        .surfaceContinuitySummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )

    guard case .surfaceContinuitySummary(let summary) = response else {
        Issue.record("Agent must return a surface continuity summary.")
        return
    }
    #expect(summary.counts.bSplineFaceCount == 2)
    #expect(summary.counts.sharedEdgeCount == 1)
    #expect(summary.counts.g1AdjacencyCount == 0)
    #expect(summary.counts.g2AdjacencyCount == 1)
    #expect(summary.counts.unresolvedG2AdjacencyCount == 0)
    let adjacency = try #require(summary.adjacencies.first)
    #expect(adjacency.continuity == .g2)
    #expect(adjacency.requiresCurvatureContinuitySolve == false)
    let curvatureGap = try #require(adjacency.curvatureGap)
    #expect(curvatureGap <= 1.0e-6)
    #expect(adjacency.edgePersistentNames.contains { $0.contains("subshape:patch:0:edge:uMax") })
    #expect(adjacency.edgePersistentNames.contains { $0.contains("subshape:patch:2:edge:uMin") })
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}
