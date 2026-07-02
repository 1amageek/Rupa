import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentConvertsSketchLineToArcThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Bendable Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .convertSketchLineToArc(
                target: target,
                sagitta: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arc = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "convertSketchLineToArc")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arc.entityKind == "arc")
    #expect(abs((arc.radius ?? -1.0) - 0.00725) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentConvertsSketchLineToSplineThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Spline Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(9.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .convertSketchLineToSpline(target: target),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let firstHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let secondHandle = try #require(spline.controlPoints.dropFirst(2).first)
    #expect(result.commandName == "convertSketchLineToSpline")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(spline.entityKind == "spline")
    #expect(spline.controlPoints.count == 4)
    #expect(abs(firstHandle.x - 0.003) < 1.0e-12)
    #expect(abs(secondHandle.x - 0.006) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentReversesSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Reverse Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(7.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .reverseSketchCurve(target: target),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let reversedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "reverseSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((reversedLine.start?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(abs((reversedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentExtendsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Extend Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(7.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try agentPointHandleSelectionTarget(line, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extendSketchCurve(
                target: target,
                distance: .length(3.0, .millimeter),
                shape: .natural
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let extendedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    #expect(result.commandName == "extendSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((extendedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((extendedLine.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentJoinsSketchCurvesThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentCollinearLineChainSketchDocument(name: "Agent Join Source Lines")
    let session = EditorSession(document: setup.document)
    let firstLineID = setup.lineIDs[0]
    let secondLineID = setup.lineIDs[1]
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let firstLine = try #require(summary.entries.first { $0.entityID == firstLineID.description })
    let secondLine = try #require(summary.entries.first { $0.entityID == secondLineID.description })

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .joinSketchCurves(
                target: try #require(firstLine.selectionTarget()),
                adjacentTarget: try #require(secondLine.selectionTarget())
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let joinedLine = try #require(updatedSummary.entries.first { $0.entityID == firstLineID.description })
    #expect(result.commandName == "joinSketchCurves")
    #expect(result.didMutate)
    #expect(result.generation == session.generation)
    #expect(updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Join Source Lines" }.count == 1)
    #expect(joinedLine.entityKind == "line")
    #expect(abs((joinedLine.start?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((joinedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentJoinsSplineEndpointsWithG2ContinuityThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoSplineTangentSketchDocument(name: "Agent Join Source Splines G2")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let firstSpline = try #require(summary.entries.first { $0.entityID == setup.firstSplineID.description })
    let secondSpline = try #require(summary.entries.first { $0.entityID == setup.secondSplineID.description })
    let firstEndpoint = try agentControlPointSelectionTarget(firstSpline, index: 3)
    let secondEndpoint = try agentControlPointSelectionTarget(secondSpline, index: 0)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .joinSketchCurves(
                target: firstEndpoint,
                adjacentTarget: secondEndpoint,
                continuity: .g2
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let feature = try #require(session.document.cadDocument.designGraph.nodes[setup.featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Agent G2 join feature must remain a sketch.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let solvedSecondSpline = try #require(updatedSummary.entries.first {
        $0.entityID == setup.secondSplineID.description
    })
    let solvedEndpoint = try #require(solvedSecondSpline.controlPoints.first)
    let solvedHandle = try #require(solvedSecondSpline.controlPoints.dropFirst().first)
    let joinedSource = try #require(session.document.productMetadata.joinedCurveGroupSources.values.first)
    let analysisResponse = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .curveAnalysis(let analysis) = analysisResponse else {
        Issue.record("Agent must return curve analysis after G2 join.")
        return
    }
    let continuityJoin = try #require(analysis.continuityJoins.first { join in
        Set([join.firstEntityID, join.secondEntityID]) == Set([
            setup.firstSplineID.description,
            setup.secondSplineID.description,
        ])
    })

    #expect(result.commandName == "joinSketchCurves")
    #expect(result.didMutate)
    #expect(joinedSource.continuity == .g2)
    #expect(sketch.constraints.contains(.smoothSplineEndpoints(
        first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
        second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
    )))
    #expect(abs(solvedEndpoint.x - 0.009) < 1.0e-12)
    #expect(abs(solvedEndpoint.y - 0.0) < 1.0e-12)
    #expect(abs(solvedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(solvedHandle.y - 0.0) < 1.0e-12)
    #expect(continuityJoin.requiredContinuity == .g2)
    #expect(continuityJoin.continuity == .g2)
    #expect(continuityJoin.constraintKinds.contains("smoothSplineEndpoints"))
    #expect(continuityJoin.constraintKinds.contains("joinedCurveGroup"))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentUnjoinsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentCollinearLineChainSketchDocument(name: "Agent Unjoin Source Lines")
    let session = EditorSession(document: setup.document)
    let firstLineID = setup.lineIDs[0]
    let secondLineID = setup.lineIDs[1]
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let firstLine = try #require(summary.entries.first { $0.entityID == firstLineID.description })
    let secondLine = try #require(summary.entries.first { $0.entityID == secondLineID.description })

    let joinResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .joinSketchCurves(
                target: try #require(firstLine.selectionTarget()),
                adjacentTarget: try #require(secondLine.selectionTarget())
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let joinResult) = joinResponse else {
        Issue.record("Agent must return a join command result.")
        return
    }
    let joinedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let joinedLine = try #require(joinedSummary.entries.first { $0.entityID == firstLineID.description })

    let unjoinResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .unjoinSketchCurve(target: try #require(joinedLine.selectionTarget())),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let unjoinResult) = unjoinResponse else {
        Issue.record("Agent must return an unjoin command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let retainedLine = try #require(updatedSummary.entries.first { $0.entityID == firstLineID.description })
    let restoredLine = try #require(updatedSummary.entries.first { $0.entityID == secondLineID.description })
    #expect(joinResult.commandName == "joinSketchCurves")
    #expect(unjoinResult.commandName == "unjoinSketchCurve")
    #expect(unjoinResult.didMutate)
    #expect(updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Unjoin Source Lines" }.count == 2)
    #expect(retainedLine.entityKind == "line")
    #expect(restoredLine.entityKind == "line")
    #expect(abs((retainedLine.end?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((restoredLine.start?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.document.productMetadata.joinedCurveSources.isEmpty)
    #expect(session.evaluationStatus == .valid)
}

private func agentControlPointSelectionTarget(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    index: Int
) throws -> SelectionTarget {
    let sceneNodeID = try #require(entry.sceneNodeID.flatMap(UUID.init(uuidString:)))
    let controlPoint = try #require(entry.controlPointTargets.first { $0.index == index })
    return SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeID),
        component: .sketchEntity(SelectionComponentID(rawValue: controlPoint.selectionComponentID))
    )
}

@MainActor
@Test func agentAppliesSketchCornerTreatmentThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Source Fillet Rectangle",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let bottomLine = try #require(agentBottomRectangleLine(in: summary))
    let target = try agentPointHandleSelectionTarget(bottomLine, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(2.0, .millimeter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter {
        $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "arc"
    }
    let filletArc = try #require(arcs.first)
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arcs.count == 1)
    #expect(abs((filletArc.center?.x ?? -1.0) - 0.008) < 1.0e-12)
    #expect(abs((filletArc.center?.y ?? -1.0) - 0.002) < 1.0e-12)
    #expect(abs((filletArc.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAppliesSketchCornerTreatmentToLineArcCornerThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.lineID.description })
    let target = try agentPointHandleSelectionTarget(sourceLine, handle: .lineEnd)

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: nil,
                distance: .length(0.001, .meter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArc = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(insertedArc.center != nil)
    #expect((sourceArc.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArc.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAppliesSketchCornerTreatmentToCurvePairThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcCornerTreatmentSketchDocument()
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.lineID.description })
    let sourceArc = try #require(summary.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceLine.selectionTarget())
    let adjacentTarget = try #require(sourceArc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySketchCornerTreatment(
                target: target,
                adjacentTarget: adjacentTarget,
                distance: .length(0.001, .meter),
                treatment: .fillet
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = updatedSummary.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    let lines = sourceEntries.filter { $0.entityKind == "line" }
    let arcs = sourceEntries.filter { $0.entityKind == "arc" }
    let insertedArc = try #require(arcs.first { abs(($0.radius ?? -1.0) - 0.001) < 1.0e-12 })
    let sourceArcAfter = try #require(arcs.first { $0.entityID == setup.arcID.description })
    #expect(result.commandName == "applySketchCornerTreatment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(lines.count == 3)
    #expect(arcs.count == 2)
    #expect(insertedArc.center != nil)
    #expect((sourceArcAfter.startAngle ?? 0.0) > 0.0)
    #expect(abs((sourceArcAfter.endAngle ?? -1.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSplitsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Split Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 2)
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(lines.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSplitsSketchArcCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Split Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(120.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let arcs = updatedSummary.entries.filter { $0.entityKind == "arc" }
    #expect(result.commandName == "splitSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(arcs.count == 2)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentTrimsSketchCurveSegmentThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Trim Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let line = try #require(summary.entries.first { $0.entityKind == "line" })
    let target = try #require(line.selectionTarget())
    let splitResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .splitSketchCurve(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command = splitResponse else {
        Issue.record("Agent must split the sketch curve before trimming.")
        return
    }
    let splitSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let trimmedLine = try #require(splitSummary.entries.first { entry in
        entry.entityKind == "line" && entry.entityID != line.entityID
    })
    let trimmedTarget = try #require(trimmedLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .trimSketchCurveSegment(target: trimmedTarget),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = updatedSummary.entries.filter { $0.entityKind == "line" }
    #expect(result.commandName == "trimSketchCurveSegment")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(lines.count == 1)
    #expect(lines.first?.entityID == line.entityID)
    #expect(abs((lines.first?.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((lines.first?.end?.x ?? -1.0) - 0.003) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(2.0, .millimeter),
                y: .length(2.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.006) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveWithCircleCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Circle Cut Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Circle Cut Cutter",
            plane: .xy,
            center: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(2.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Cut Target" })
    let cutterCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Cut Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterCircle.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Cut Target" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 3)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.003) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.003) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.007) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.007) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCurveWithSplineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Spline Cutter Target",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Spline Cutter",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(5.0, .millimeter), y: .length(-2.0, .millimeter)),
                SketchPoint(x: .length(5.0, .millimeter), y: .length(-2.0 / 3.0, .millimeter)),
                SketchPoint(x: .length(5.0, .millimeter), y: .length(2.0 / 3.0, .millimeter)),
                SketchPoint(x: .length(5.0, .millimeter), y: .length(2.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cutter Target" })
    let cutterSpline = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cutter" })
    let target = try #require(targetLine.selectionTarget())
    let cutter = try #require(cutterSpline.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Spline Cutter Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Spline Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.005) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.start?.x ?? -1.0) - 0.005) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchSplineTargetWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Spline Cut Target",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Spline Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(-1.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(5.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetSpline = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Spline Cut Cutter" })
    let target = try #require(targetSpline.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Spline Cut Target" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "spline" })
    #expect(targetSegments.contains { entry in
        guard let start = entry.controlPoints.first,
              let end = entry.controlPoints.last else {
            return false
        }
        return abs(start.x - 0.0) < 1.0e-9 &&
            abs(start.y - 0.0) < 1.0e-9 &&
            abs(end.x - 0.005) < 1.0e-9 &&
            abs(end.y - 0.003) < 1.0e-9
    })
    #expect(targetSegments.contains { entry in
        guard let start = entry.controlPoints.first,
              let end = entry.controlPoints.last else {
            return false
        }
        return abs(start.x - 0.005) < 1.0e-9 &&
            abs(start.y - 0.003) < 1.0e-9 &&
            abs(end.x - 0.010) < 1.0e-9 &&
            abs(end.y - 0.0) < 1.0e-9
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchCircleTargetWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Circle Target Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Circle Target Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-6.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetCircle = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Target Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Circle Target Cut Cutter" })
    let target = try #require(targetCircle.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Target Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Circle Target Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(targetSegments.allSatisfy { $0.entityKind == "arc" })
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi * 1.5) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi * 1.5) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCutsSketchArcCurveWithLineCutterThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Arc Cut Target",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi, .radian)
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Arc Cut Cutter",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(-2.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch entity summary.")
        return
    }
    let targetArc = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Arc Cut Target" })
    let cutterLine = try #require(summary.entries.first { $0.sourceFeatureName == "Agent Arc Cut Cutter" })
    let target = try #require(targetArc.selectionTarget())
    let cutter = try #require(cutterLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .cutSketchCurve(
                target: target,
                cutter: cutter,
                options: CutCurveOptions()
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let targetSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Arc Cut Target" }
    let cutterSegments = updatedSummary.entries.filter { $0.sourceFeatureName == "Agent Arc Cut Cutter" }
    #expect(result.commandName == "cutSketchCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(targetSegments.count == 2)
    #expect(cutterSegments.count == 1)
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12
    })
    #expect(targetSegments.contains { entry in
        abs((entry.startAngle ?? -1.0) - Double.pi / 2.0) < 1.0e-12 &&
            abs((entry.endAngle ?? -1.0) - Double.pi) < 1.0e-12
    })
    #expect(session.evaluationStatus == .valid)
}
