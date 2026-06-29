import Foundation
import Testing
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentTogglesSurfaceControlPointDisplayThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface CV Display",
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
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })

    let displayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceControlPointDisplay(
                target: controlPoint.selectionReference,
                isVisible: true
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let displayResult) = displayResponse else {
        Issue.record("Agent must set a surface control point display state.")
        return
    }
    #expect(displayResult.commandName == "setSurfaceControlPointDisplay")
    #expect(displayResult.didMutate)
    #expect(displayResult.generation == DocumentGeneration(2))

    let visibleSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let visibleSummary) = visibleSummaryResponse else {
        Issue.record("Agent must return an updated surface source summary.")
        return
    }
    let visiblePatch = try #require(visibleSummary.sources.first?.patches.first)
    let visibleControlPoint = try #require(visiblePatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    #expect(visibleControlPoint.isPointDisplayVisible)
}

@MainActor
@Test func agentTogglesSurfaceFrameDisplayThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Frame Display",
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
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 2 && $0.vIndex == 1 })
    let query = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)

    let displayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceFrameDisplay(
                query: query,
                isVisible: true
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let displayResult) = displayResponse else {
        Issue.record("Agent must set a surface frame display state.")
        return
    }
    #expect(displayResult.commandName == "setSurfaceFrameDisplay")
    #expect(displayResult.didMutate)
    #expect(displayResult.generation == DocumentGeneration(2))

    let displayID = try SurfaceFrameDisplayID(query: query)
    #expect(session.document.productMetadata.surfaceFrameDisplays[displayID]?.isVisible == true)

    let frameResponse = server.handle(
        .surfaceFrames(
            sessionID: sessionID,
            queries: [query],
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceFrames(let frames) = frameResponse else {
        Issue.record("Agent must resolve the displayed surface frame.")
        return
    }
    let frame = try #require(frames.frames.first)
    #expect(abs(frame.u - (2.0 / 3.0)) <= 1.0e-12)
    #expect(abs(frame.v - (1.0 / 3.0)) <= 1.0e-12)
}

@MainActor
@Test func agentResolvesTrimParameterCurveSurfaceFramesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Trim Frame Surface",
                surface: agentDirectBSplineSurfaceWithInteriorKnots()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a direct B-spline surface.")
        return
    }
    #expect(createResult.didMutate)

    let initialSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let initialSummary) = initialSummaryResponse else {
        Issue.record("Agent must discover direct B-spline surface references.")
        return
    }
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    let trimResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceTrimLoops(
                target: faceReference,
                trimLoops: [agentAuthoredBSplineSurfaceTrimLoop()]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let trimResult) = trimResponse else {
        Issue.record("Agent must set authored trim loops.")
        return
    }
    #expect(trimResult.didMutate)

    let generation = session.generation
    let dirty = session.isDirty
    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must discover authored trim p-curve references.")
        return
    }
    let trimEdge = try #require(summary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let spanSelection = try #require(trimEdge.parameterCurve.spans.first?.selectionReference)
    let knotSelection = try #require(trimEdge.parameterCurve.knotVector.first?.selectionReference)
    let spanQuery = SurfaceFrameQuery(selectionReference: spanSelection)
    let knotQuery = SurfaceFrameQuery(selectionReference: knotSelection)
    let frameResponse = server.handle(
        .surfaceFrames(
            sessionID: sessionID,
            queries: [spanQuery, knotQuery],
            expectedGeneration: generation
        )
    )
    guard case .surfaceFrames(let frames) = frameResponse else {
        Issue.record("Agent must resolve trim p-curve UVN frames.")
        return
    }

    #expect(frames.frames.count == 2)
    let spanFrame = try #require(frames.frames.first)
    let knotFrame = try #require(frames.frames.dropFirst().first)
    #expect(abs(spanFrame.u - 0.51) <= 1.0e-12)
    #expect(abs(spanFrame.v - 0.3225) <= 1.0e-12)
    #expect(abs(knotFrame.u - 0.2) <= 1.0e-12)
    #expect(abs(knotFrame.v - 0.2) <= 1.0e-12)
    #expect(abs(surfaceVectorLength(spanFrame.normal) - 1.0) <= 1.0e-8)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)

    let displayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceFrameDisplay(query: spanQuery, isVisible: true),
            expectedGeneration: generation
        )
    )
    guard case .command(let displayResult) = displayResponse else {
        Issue.record("Agent must persist a trim p-curve frame display.")
        return
    }
    #expect(displayResult.commandName == "setSurfaceFrameDisplay")
    #expect(displayResult.didMutate)
    let displayID = try SurfaceFrameDisplayID(query: spanQuery)
    #expect(session.document.productMetadata.surfaceFrameDisplays[displayID]?.isVisible == true)
}

@MainActor
@Test func agentResolvesPlanarPolySplineSurfaceFramesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolySplineSurface(
                name: "Agent Surface Frame",
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

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse,
          let faceEntry = topology.entries.first(where: { $0.kind == .face }) else {
        Issue.record("Agent must discover generated face topology before resolving UVN frames.")
        return
    }
    let sourceResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: generation
        )
    )
    guard case .surfaceSourceSummary(let surfaceSources) = sourceResponse,
          let source = surfaceSources.sources.first,
          let patch = source.patches.first,
          let faceSelectionReference = patch.faceSelectionReference,
          let controlPoint = patch.controlPoints.first(where: { $0.uIndex == 2 && $0.vIndex == 1 }) else {
        Issue.record("Agent must discover Surface source references before resolving selection-based UVN frames.")
        return
    }

    let response = server.handle(
        .surfaceFrames(
            sessionID: sessionID,
            queries: [
                SurfaceFrameQuery(
                    facePersistentName: faceEntry.persistentName,
                    u: 0.5,
                    v: 0.5
                ),
                SurfaceFrameQuery(
                    selectionReference: faceSelectionReference,
                    u: 0.25,
                    v: 0.75
                ),
                SurfaceFrameQuery(
                    selectionReference: controlPoint.selectionReference
                ),
            ],
            expectedGeneration: generation
        )
    )

    guard case .surfaceFrames(let frames) = response else {
        Issue.record("Agent must return surface frame data.")
        return
    }
    #expect(frames.frames.count == 3)
    let frame = try #require(frames.frames.first)
    #expect(frame.facePersistentNames.contains(faceEntry.persistentName))
    #expect(abs(surfaceVectorLength(frame.uAxis) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorLength(frame.vAxis) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorLength(frame.normal) - 1.0) <= 1.0e-8)
    #expect(abs(surfaceVectorDot(surfaceVectorCross(frame.uAxis, frame.vAxis), frame.normal) - 1.0) <= 1.0e-8)
    #expect(frame.handedness > 0.999_999)
    #expect(abs(frame.normalCurvatureU) <= 1.0e-8)
    #expect(abs(frame.normalCurvatureV) <= 1.0e-8)
    let faceSelectionFrame = try #require(frames.frames.dropFirst().first)
    #expect(faceSelectionFrame.facePersistentNames.contains(faceEntry.persistentName))
    #expect(abs(faceSelectionFrame.u - 0.25) <= 1.0e-12)
    #expect(abs(faceSelectionFrame.v - 0.75) <= 1.0e-12)
    let controlPointFrame = try #require(frames.frames.dropFirst(2).first)
    #expect(controlPointFrame.facePersistentNames.contains(faceEntry.persistentName))
    #expect(abs(controlPointFrame.u - (2.0 / 3.0)) <= 1.0e-12)
    #expect(abs(controlPointFrame.v - (1.0 / 3.0)) <= 1.0e-12)
    #expect(session.generation == generation)
    #expect(session.isDirty == dirty)
}
