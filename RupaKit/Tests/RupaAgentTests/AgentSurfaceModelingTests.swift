import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentDispatchesDirectBSplineSurfaceCommandAndExposesSourceSummary() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent B-spline Surface",
                surface: agentDirectBSplineSurface()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must create a direct B-spline surface.")
        return
    }
    #expect(result.commandName == "createBSplineSurface")
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
        Issue.record("Agent must return topology for a direct B-spline surface.")
        return
    }
    let face = try #require(topology.entries.first {
        $0.kind == .face
            && $0.surfaceKind == "bSpline"
            && $0.generatedRole == "bSplineSurface"
            && $0.subshapeRole == "patch:0:face"
    })
    #expect(face.surfaceUDegree == 3)
    #expect(face.surfaceVDegree == 3)
    #expect(face.surfaceUControlPointCount == 4)
    #expect(face.surfaceVControlPointCount == 4)

    let sourceResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = sourceResponse else {
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let source = try #require(summary.sources.first)
    #expect(source.kind == "bSplineSurface")
    let patch = try #require(source.patches.first)
    #expect(patch.basis.kind == "bSplineSurface")
    #expect(patch.basis.isRational)
    let trimLoop = try #require(patch.trimLoops.first)
    #expect(trimLoop.edges.map(\.role) == ["vMin", "uMax", "vMax", "uMin"])
    #expect(trimLoop.edges.allSatisfy { $0.supportedBoundaryContinuityLevels == [.g0, .g1, .g2] })
    #expect(trimLoop.edges.allSatisfy { $0.supportsBoundaryContinuityMatching })
    let firstTrimEdge = try #require(trimLoop.edges.first)
    #expect(firstTrimEdge.boundaryControlPointReferences.count == 4)
    #expect(firstTrimEdge.firstInwardControlPointReferences.count == 4)
    #expect(firstTrimEdge.secondInwardControlPointReferences.count == 4)
    let weightedControlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    #expect(weightedControlPoint.weight == 2.0)
    #expect(weightedControlPoint.isEditable)
}

@MainActor
@Test func agentEditsDirectBSplineSurfaceControlPointThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Editable B-spline Surface",
                surface: agentDirectBSplineSurface()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a direct B-spline surface.")
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
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let controlPoint = try #require(
        summary.sources.first?.patches.first?.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    #expect(controlPoint.isEditable)

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
        Issue.record("Agent must move a direct B-spline surface control point.")
        return
    }
    #expect(moveResult.commandName == "moveSurfaceControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))

    let weightResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceControlPointWeight(
                target: controlPoint.selectionReference,
                weight: .scalar(2.5)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let weightResult) = weightResponse else {
        Issue.record("Agent must set a direct B-spline surface control point weight.")
        return
    }
    #expect(weightResult.commandName == "setSurfaceControlPointWeight")
    #expect(weightResult.didMutate)
    #expect(weightResult.generation == DocumentGeneration(3))

    let slideResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slideSurfaceControlPoints(
                targets: [controlPoint.selectionReference],
                direction: .positiveU,
                distance: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .command(let slideResult) = slideResponse else {
        Issue.record("Agent must slide a direct B-spline surface control point.")
        return
    }
    #expect(slideResult.commandName == "slideSurfaceControlPoints")
    #expect(slideResult.didMutate)
    #expect(slideResult.generation == DocumentGeneration(4))

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent must keep a direct B-spline surface feature.")
        return
    }
    let storedPoint = surfaceFeature.surface.controlPoints[1][1]
    #expect(abs(storedPoint.x - (controlPoint.point.x + 0.001)) <= 1.0e-12)
    #expect(abs(storedPoint.y - controlPoint.point.y) <= 1.0e-12)
    #expect(abs(storedPoint.z - (controlPoint.point.z + 0.001)) <= 1.0e-12)
    #expect(surfaceFeature.surface.weights[1][1] == 2.5)
    #expect(session.evaluationStatus == .valid)

    let updatedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(4)
        )
    )
    guard case .surfaceSourceSummary(let updatedSummary) = updatedSummaryResponse else {
        Issue.record("Agent must return updated direct B-spline surface source summary.")
        return
    }
    let updatedPatch = try #require(updatedSummary.sources.first?.patches.first)
    let updatedControlPoint = try #require(
        updatedPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    #expect(updatedPatch.basis.isRational)
    #expect(updatedControlPoint.weight == 2.5)
    #expect(abs(updatedControlPoint.point.x - storedPoint.x) <= 1.0e-12)
    #expect(abs(updatedControlPoint.point.z - storedPoint.z) <= 1.0e-12)
}

@MainActor
@Test func agentMovesDirectBSplineSurfaceControlPointThroughResolvedFrameSample() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Frame Editable Surface",
                surface: agentDirectBSplineSurface()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a direct B-spline surface.")
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
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(
        patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    let frameSample = try #require(patch.frameSamples.first)
    let frameQuery = SurfaceFrameQuery(selectionReference: frameSample.selectionReference)
    let frameResponse = server.handle(
        .surfaceFrames(
            sessionID: sessionID,
            queries: [frameQuery],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceFrames(let frames) = frameResponse,
          let frame = frames.frames.first else {
        Issue.record("Agent must resolve the discovered surface frame sample.")
        return
    }

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSurfaceControlPointsInFrame(
                targets: [controlPoint.selectionReference],
                frame: frameQuery,
                uDistance: .length(1.0, .millimeter),
                vDistance: .length(2.0, .millimeter),
                normalDistance: .length(3.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move a direct B-spline surface control point in a resolved frame.")
        return
    }
    #expect(moveResult.commandName == "moveSurfaceControlPointsInFrame")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent must keep a direct B-spline surface feature.")
        return
    }
    let movedPoint = surfaceFeature.surface.controlPoints[1][1]
    let expectedX = controlPoint.point.x
        + frame.uAxis.x * 0.001
        + frame.vAxis.x * 0.002
        + frame.normal.x * 0.003
    let expectedY = controlPoint.point.y
        + frame.uAxis.y * 0.001
        + frame.vAxis.y * 0.002
        + frame.normal.y * 0.003
    let expectedZ = controlPoint.point.z
        + frame.uAxis.z * 0.001
        + frame.vAxis.z * 0.002
        + frame.normal.z * 0.003
    #expect(abs(movedPoint.x - expectedX) <= 1.0e-12)
    #expect(abs(movedPoint.y - expectedY) <= 1.0e-12)
    #expect(abs(movedPoint.z - expectedZ) <= 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentEditsDirectBSplineSurfaceKnotThroughSurfaceSourceReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Editable B-spline Knot Surface",
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

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let knot = try #require(
        summary.sources.first?.patches.first?.basis.uKnotVector.first { $0.index == 3 }
    )
    #expect(knot.isEditable)
    let knotReference = try #require(knot.selectionReference)

    let knotResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceKnotValue(
                target: knotReference,
                value: .scalar(0.4)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let knotResult) = knotResponse else {
        Issue.record("Agent must set a direct B-spline surface knot value.")
        return
    }
    #expect(knotResult.commandName == "setSurfaceKnotValue")
    #expect(knotResult.didMutate)
    #expect(knotResult.generation == DocumentGeneration(2))

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent must keep a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots[3] == 0.4)
    #expect(surfaceFeature.surface.vKnots[3] == 0.5)
    #expect(session.evaluationStatus == .valid)

    let updatedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let updatedSummary) = updatedSummaryResponse else {
        Issue.record("Agent must return updated direct B-spline surface source summary.")
        return
    }
    let updatedKnot = try #require(
        updatedSummary.sources.first?.patches.first?.basis.uKnotVector.first { $0.index == 3 }
    )
    #expect(updatedKnot.value == 0.4)
    #expect(updatedKnot.isEditable)
}

@MainActor
@Test func agentInsertsDirectBSplineSurfaceKnotThroughSurfaceSourceSpanReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Insertable B-spline Knot Surface",
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

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let span = try #require(
        summary.sources.first?.patches.first?.basis.uSpans.first { $0.index == 0 }
    )
    #expect(span.isEditable)
    let spanReference = try #require(span.selectionReference)

    let insertionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .insertSurfaceKnot(
                target: spanReference,
                value: .scalar(0.25)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let insertionResult) = insertionResponse else {
        Issue.record("Agent must insert a direct B-spline surface knot.")
        return
    }
    #expect(insertionResult.commandName == "insertSurfaceKnot")
    #expect(insertionResult.didMutate)
    #expect(insertionResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent must keep a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.25, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.uControlPointCount == 5)
    #expect(surfaceFeature.surface.vControlPointCount == 4)

    let updatedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let updatedSummary) = updatedSummaryResponse else {
        Issue.record("Agent must return updated direct B-spline surface source summary.")
        return
    }
    let updatedPatch = try #require(updatedSummary.sources.first?.patches.first)
    #expect(updatedPatch.basis.uSpans.count == 3)
    #expect(updatedPatch.controlPoints.count == 20)
}

@MainActor
@Test func agentInsertsDuplicateDirectBSplineSurfaceKnotThroughSurfaceSourceKnotReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Multiplicity B-spline Knot Surface",
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

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let knot = try #require(
        summary.sources.first?.patches.first?.basis.uKnotVector.first { $0.index == 3 }
    )
    #expect(knot.isEditable)
    let knotReference = try #require(knot.selectionReference)

    let insertionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .insertSurfaceKnot(
                target: knotReference,
                value: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let insertionResult) = insertionResponse else {
        Issue.record("Agent must insert a duplicate direct B-spline surface knot.")
        return
    }
    #expect(insertionResult.commandName == "insertSurfaceKnot")
    #expect(insertionResult.didMutate)
    #expect(insertionResult.generation == DocumentGeneration(2))

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent must keep a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.uControlPointCount == 5)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSplitsDirectBSplineSurfaceSpanThroughSurfaceSourceSpanReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Split Span B-spline Surface",
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

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let span = try #require(
        summary.sources.first?.patches.first?.basis.vSpans.first { $0.index == 1 }
    )
    #expect(span.lowerBound == 0.5)
    #expect(span.upperBound == 1.0)
    let spanReference = try #require(span.selectionReference)

    let splitResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSurfaceSpan(
                target: spanReference,
                fraction: .scalar(0.25)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let splitResult) = splitResponse else {
        Issue.record("Agent must split a direct B-spline surface span.")
        return
    }
    #expect(splitResult.commandName == "splitSurfaceSpan")
    #expect(splitResult.didMutate)
    #expect(splitResult.generation == DocumentGeneration(2))

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent must keep a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.vKnots == [0.0, 0.0, 0.0, 0.5, 0.625, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.uControlPointCount == 4)
    #expect(surfaceFeature.surface.vControlPointCount == 5)
    #expect(session.evaluationStatus == .valid)

    let staleResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSurfaceSpan(
                target: spanReference,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .failure(let staleError) = staleResponse else {
        Issue.record("Agent must reject stale span split generations.")
        return
    }
    #expect(staleError.code == .documentGenerationMismatch)
}

@MainActor
@Test func agentSetsDirectBSplineSurfaceKnotMultiplicityThroughSurfaceSourceKnotReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Explicit Multiplicity B-spline Knot Surface",
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

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return direct B-spline surface source summary.")
        return
    }
    let knot = try #require(
        summary.sources.first?.patches.first?.basis.uKnotVector.first { $0.index == 3 }
    )
    #expect(knot.value == 0.5)
    #expect(knot.multiplicity == 1)
    #expect(knot.isEditable)
    let knotReference = try #require(knot.selectionReference)

    let multiplicityResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceKnotMultiplicity(
                target: knotReference,
                multiplicity: 2
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let multiplicityResult) = multiplicityResponse else {
        Issue.record("Agent must set a direct B-spline surface knot multiplicity.")
        return
    }
    #expect(multiplicityResult.commandName == "setSurfaceKnotMultiplicity")
    #expect(multiplicityResult.didMutate)
    #expect(multiplicityResult.generation == DocumentGeneration(2))

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent must keep a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.uControlPointCount == 5)
    #expect(session.evaluationStatus == .valid)

    let updatedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let updatedSummary) = updatedSummaryResponse else {
        Issue.record("Agent must return updated direct B-spline surface source summary.")
        return
    }
    let repeatedKnots = try #require(
        updatedSummary.sources.first?.patches.first?.basis.uKnotVector.filter { $0.value == 0.5 }
    )
    #expect(repeatedKnots.count == 2)
    #expect(repeatedKnots.allSatisfy { $0.multiplicity == 2 })
}

@MainActor
@Test func agentMovesDirectBSplineSurfaceTrimEndpointThroughAuthoredTrimReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Trim Endpoint Surface",
                surface: agentDirectBSplineSurfaceWithInteriorKnots()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a direct B-spline surface for trim endpoint editing.")
        return
    }
    #expect(createResult.commandName == "createBSplineSurface")

    let initialSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let initialSummary) = initialSummaryResponse else {
        Issue.record("Agent must return a surface source summary before trim endpoint editing.")
        return
    }
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.2, v: 0.2),
                SurfaceParameter(u: 0.8, v: 0.25),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )

    let setLoopsResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceTrimLoops(
                target: faceReference,
                trimLoops: [trimLoop]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setLoopsResult) = setLoopsResponse else {
        Issue.record("Agent must set authored trim loops before endpoint editing.")
        return
    }
    #expect(setLoopsResult.commandName == "setSurfaceTrimLoops")
    #expect(setLoopsResult.didMutate)

    let trimmedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let trimmedSummary) = trimmedSummaryResponse else {
        Issue.record("Agent must return authored trim loop references.")
        return
    }
    let trimReference = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first
    )

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSurfaceTrimEndpoint(
                target: trimReference,
                endpoint: .start,
                u: .scalar(0.25),
                v: .scalar(0.3)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move the authored surface trim endpoint.")
        return
    }
    #expect(moveResult.commandName == "moveSurfaceTrimEndpoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent trim endpoint edit must keep a direct B-spline surface feature.")
        return
    }
    let movedLoop = try #require(surfaceFeature.trimLoops.first)
    #expect(try movedLoop.edges[0].startParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.25, v: 0.3),
        tolerance: 1.0e-12
    ))
    #expect(try movedLoop.edges[2].endParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.25, v: 0.3),
        tolerance: 1.0e-12
    ))
}

@MainActor
@Test func agentMovesDirectBSplineSurfaceTrimControlPointThroughAuthoredTrimReference() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Trim Control Point Surface",
                surface: agentDirectBSplineSurfaceWithInteriorKnots()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a direct B-spline surface for trim control point editing.")
        return
    }
    #expect(createResult.commandName == "createBSplineSurface")

    let initialSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .surfaceSourceSummary(let initialSummary) = initialSummaryResponse else {
        Issue.record("Agent must return a surface source summary before trim control point editing.")
        return
    }
    let faceReference = try #require(initialSummary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )

    let setLoopsResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceTrimLoops(
                target: faceReference,
                trimLoops: [trimLoop]
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setLoopsResult) = setLoopsResponse else {
        Issue.record("Agent must set authored trim loops before control point editing.")
        return
    }
    #expect(setLoopsResult.commandName == "setSurfaceTrimLoops")
    #expect(setLoopsResult.didMutate)

    let trimmedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let trimmedSummary) = trimmedSummaryResponse else {
        Issue.record("Agent must return authored trim loop references.")
        return
    }
    let authoredTrimEdge = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.edges.first
    )
    let trimReference = try #require(authoredTrimEdge.selectionReference)
    let editableControlPoint = try #require(
        authoredTrimEdge.parameterCurveControlPoints.first { $0.isEditable }
    )
    #expect(editableControlPoint.index == 1)
    #expect(abs(editableControlPoint.parameter.u - 0.52) <= 1.0e-12)
    #expect(abs(editableControlPoint.parameter.v - 0.42) <= 1.0e-12)

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSurfaceTrimControlPoint(
                target: trimReference,
                controlPointIndex: editableControlPoint.index,
                u: .scalar(0.58),
                v: .scalar(0.46)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must move the authored surface trim control point.")
        return
    }
    #expect(moveResult.commandName == "moveSurfaceTrimControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)

    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Agent trim control point edit must keep a direct B-spline surface feature.")
        return
    }
    let movedLoop = try #require(surfaceFeature.trimLoops.first)
    guard case .bSpline(let movedCurve) = movedLoop.edges[0].parameterCurve else {
        Issue.record("Agent must keep the authored B-spline trim p-curve.")
        return
    }
    #expect(movedCurve.controlPoints[0] == Point2D(x: 0.2, y: 0.2))
    #expect(movedCurve.controlPoints[1] == Point2D(x: 0.58, y: 0.46))
    #expect(movedCurve.controlPoints[2] == Point2D(x: 0.8, y: 0.25))

    let weightResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceTrimControlPointWeight(
                target: trimReference,
                controlPointIndex: editableControlPoint.index,
                weight: .scalar(2.4)
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .command(let weightResult) = weightResponse else {
        Issue.record("Agent must set the authored surface trim control point weight.")
        return
    }
    #expect(weightResult.commandName == "setSurfaceTrimControlPointWeight")
    #expect(weightResult.didMutate)
    #expect(weightResult.generation == DocumentGeneration(4))

    let weightedFeature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(weightedSurfaceFeature) = weightedFeature.operation,
          let weightedLoop = weightedSurfaceFeature.trimLoops.first,
          case .bSpline(let weightedCurve) = weightedLoop.edges[0].parameterCurve else {
        Issue.record("Agent trim weight edit must keep the authored B-spline trim p-curve.")
        return
    }
    #expect(weightedCurve.weights == [1.0, 2.4, 1.0])

    let weightedSummaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(4)
        )
    )
    guard case .surfaceSourceSummary(let weightedSummary) = weightedSummaryResponse else {
        Issue.record("Agent must return weighted authored trim p-curve source summary.")
        return
    }
    let weightedSummaryEdge = try #require(
        weightedSummary.sources.first?.patches.first?.trimLoops.first?.edges.first
    )
    let weightedSummaryPoint = try #require(
        weightedSummaryEdge.parameterCurveControlPoints.first { $0.index == editableControlPoint.index }
    )
    #expect(weightedSummaryPoint.weight == 2.4)
    #expect(weightedSummaryPoint.isWeightEditable)
}

@MainActor
@Test func agentMatchesDirectBSplineSurfaceBoundaryContinuityThroughTrimReferences() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let referenceResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Reference Boundary Surface",
                surface: agentDirectBSplineSurface()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let referenceResult) = referenceResponse else {
        Issue.record("Agent must create a reference direct B-spline surface.")
        return
    }
    #expect(referenceResult.didMutate)

    let targetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Target Boundary Surface",
                surface: agentOffsetDirectBSplineSurface()
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let targetResult) = targetResponse else {
        Issue.record("Agent must create a target direct B-spline surface.")
        return
    }
    #expect(targetResult.didMutate)

    let featureIDs = session.document.cadDocument.designGraph.order
    let referenceFeatureID = try #require(featureIDs.first)
    let targetFeatureID = try #require(featureIDs.last)
    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return surface source summary for boundary matching.")
        return
    }
    let referenceSource = try #require(summary.sources.first { $0.featureID == referenceFeatureID.description })
    let targetSource = try #require(summary.sources.first { $0.featureID == targetFeatureID.description })
    let referenceTrimLoop = try #require(referenceSource.patches.first?.trimLoops.first)
    let targetTrimLoop = try #require(targetSource.patches.first?.trimLoops.first)
    guard referenceTrimLoop.selectionReferences.indices.contains(2),
          targetTrimLoop.selectionReferences.indices.contains(0) else {
        Issue.record("Agent boundary match requires direct B-spline trim references.")
        return
    }
    let referenceTrim = referenceTrimLoop.selectionReferences[2]
    let targetTrim = targetTrimLoop.selectionReferences[0]

    let matchResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .matchSurfaceBoundaryContinuity(
                target: targetTrim,
                reference: referenceTrim,
                level: .g1,
                matchSide: .opposite,
                referenceDirection: .forward
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let matchResult) = matchResponse else {
        Issue.record("Agent must match direct B-spline surface boundary continuity.")
        return
    }
    #expect(matchResult.commandName == "matchSurfaceBoundaryContinuity")
    #expect(matchResult.didMutate)
    #expect(matchResult.generation == DocumentGeneration(3))

    let targetFeature = try #require(session.document.cadDocument.designGraph.nodes[targetFeatureID])
    let referenceFeature = try #require(session.document.cadDocument.designGraph.nodes[referenceFeatureID])
    guard case let .bSplineSurface(targetSurfaceFeature) = targetFeature.operation,
          case let .bSplineSurface(referenceSurfaceFeature) = referenceFeature.operation else {
        Issue.record("Agent boundary match must keep direct B-spline surface features.")
        return
    }
    let referenceBoundary = referenceSurfaceFeature.surface.controlPoints[3][2]
    let referenceInward = referenceSurfaceFeature.surface.controlPoints[2][2] - referenceBoundary
    #expect(targetSurfaceFeature.surface.controlPoints[0][2].isApproximatelyEqual(
        to: referenceBoundary,
        tolerance: 1.0e-12
    ))
    #expect(targetSurfaceFeature.surface.controlPoints[1][2].isApproximatelyEqual(
        to: referenceBoundary + (-referenceInward),
        tolerance: 1.0e-12
    ))
    #expect(session.evaluationStatus == .valid)
}

@Test func agentPreflightsDirectBSplineSurfaceBoundaryContinuityCompatibilityWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let referenceResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Reference Compatibility Surface",
                surface: agentDirectBSplineSurface()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let referenceResult) = referenceResponse else {
        Issue.record("Agent must create a reference direct B-spline surface.")
        return
    }
    #expect(referenceResult.didMutate)

    let targetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Target Compatibility Surface",
                surface: agentOffsetDirectBSplineSurface()
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let targetResult) = targetResponse else {
        Issue.record("Agent must create a target direct B-spline surface.")
        return
    }
    #expect(targetResult.didMutate)

    let featureIDs = session.document.cadDocument.designGraph.order
    let referenceFeatureID = try #require(featureIDs.first)
    let targetFeatureID = try #require(featureIDs.last)
    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must return surface source summary for boundary compatibility.")
        return
    }
    let referenceSource = try #require(summary.sources.first { $0.featureID == referenceFeatureID.description })
    let targetSource = try #require(summary.sources.first { $0.featureID == targetFeatureID.description })
    let referenceTrim = try #require(referenceSource.patches.first?.trimLoops.first?.selectionReferences[2])
    let targetTrim = try #require(targetSource.patches.first?.trimLoops.first?.selectionReferences[0])

    let compatibilityResponse = server.handle(
        .surfaceBoundaryContinuityCompatibility(
            sessionID: sessionID,
            target: targetTrim,
            reference: referenceTrim,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceBoundaryContinuityCompatibility(let compatibility) = compatibilityResponse else {
        Issue.record("Agent must return boundary continuity compatibility.")
        return
    }
    #expect(compatibility.status == .compatible)
    #expect(compatibility.maximumSupportedContinuityLevel == .g2)
    #expect(compatibility.recommendedMatchSide == .opposite)
    #expect(session.generation == DocumentGeneration(2))

    let staleResponse = server.handle(
        .surfaceBoundaryContinuityCompatibility(
            sessionID: sessionID,
            target: targetTrim,
            reference: referenceTrim,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .failure(let error) = staleResponse else {
        Issue.record("Agent must reject stale boundary compatibility preflight.")
        return
    }
    #expect(error.code == .documentGenerationMismatch)
}

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
    #expect(summary.counts.frameSampleCount == 2)
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
    let frameSample = try #require(patch.frameSamples.first)
    let frameResponse = server.handle(
        .surfaceFrames(
            sessionID: sessionID,
            queries: [SurfaceFrameQuery(selectionReference: frameSample.selectionReference)],
            expectedGeneration: generation
        )
    )
    guard case .surfaceFrames(let frames) = frameResponse,
          let resolvedFrame = frames.frames.first else {
        Issue.record("Agent must resolve a discovered surface frame sample selection reference.")
        return
    }
    #expect(abs(resolvedFrame.u - frameSample.u) <= 1.0e-12)
    #expect(abs(resolvedFrame.v - frameSample.v) <= 1.0e-12)
    #expect(patch.trimLoops.first?.edgePersistentNames.count == 4)
    #expect(patch.trimLoops.first?.selectionReferences.count == 4)
    let trimLoop = try #require(patch.trimLoops.first)
    #expect(trimLoop.edges.map(\.role) == ["vMin", "uMax", "vMax", "uMin"])
    #expect(trimLoop.edges.allSatisfy { $0.selectionReference != nil })
    #expect(trimLoop.edges.allSatisfy { $0.supportsBoundaryContinuityMatching == false })
    #expect(trimLoop.edges.allSatisfy { $0.unsupportedReason?.contains("PolySpline") == true })
    let trimEdge = try #require(trimLoop.edges.first)
    #expect(trimEdge.boundaryControlPointReferences.count == 4)
    #expect(trimEdge.firstInwardControlPointReferences.count == 4)
    #expect(trimEdge.secondInwardControlPointReferences.count == 4)
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
