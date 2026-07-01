import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentAnalyzesOpenSessionCurvesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Analysis Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 1)
    let spline = try #require(analysis.curves.first { $0.curveKind == .spline })
    #expect(spline.samples.count == 17)
    #expect(spline.maxAbsCurvature > 1.0)
    #expect(spline.selectionComponentID?.hasPrefix(SelectionComponentID.sketchEntityPrefix) == true)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentAnalyzesConstrainedEndpointContinuityWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Curve Continuity")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let constraintResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .coincident(.lineEnd(setup.firstLineID), .lineStart(setup.secondLineID))
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command = constraintResponse else {
        #expect(Bool(false))
        return
    }

    let response = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = response else {
        #expect(Bool(false))
        return
    }
    #expect(analysis.counts.curveCount == 2)
    #expect(analysis.counts.continuityJoinCount == 1)
    let join = try #require(analysis.continuityJoins.first)
    #expect(join.joinKind == .constrainedEndpoint)
    #expect(join.constraintKinds == ["coincident"])
    #expect(join.requiredContinuity == .g0)
    #expect(join.firstReference == "lineEnd:\(setup.firstLineID.description)")
    #expect(join.secondReference == "lineStart:\(setup.secondLineID.description)")
    #expect(join.continuity == .g0)
    #expect(abs(join.positionGap) < 1.0e-12)
    #expect((join.tangentAngle ?? 0.0) > 1.0e-4)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesBridgeCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Bridge Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBridgeCurve(
                featureID: setup.featureID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: .lineEnd(setup.firstLineID)
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: .lineStart(setup.secondLineID)
                ),
                continuity: .g1
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: setup.featureID))
    let bridgeID = try #require(sketch.entities.first { _, entity in
        if case .spline = entity {
            return true
        }
        return false
    }?.key)
    let source = try #require(session.document.productMetadata.bridgeCurveSources.values.first)
    let analysisResponse = server.handle(
        .curveAnalysis(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .curveAnalysis(let analysis) = analysisResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createBridgeCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.entities.count == 3)
    #expect(source.featureID == setup.featureID)
    #expect(source.entityID == bridgeID)
    #expect(source.firstEndpoint.reference == .lineEnd(setup.firstLineID))
    #expect(source.secondEndpoint.reference == .lineStart(setup.secondLineID))
    #expect(source.continuity == .g1)
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineEnd(setup.firstLineID)
    )))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineStart(setup.secondLineID)
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .start,
        line: setup.firstLineID
    )))
    let bridgeCurve = try #require(analysis.curves.first { $0.entityID == bridgeID.description })
    #expect(bridgeCurve.curveKind == .spline)
    #expect(analysis.continuityJoins.contains { join in
        join.firstEntityID == bridgeID.description || join.secondEntityID == bridgeID.description
    })

    let updateResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setBridgeCurveParameters(
                sourceID: source.id,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: .entity(setup.firstLineID),
                    parameter: .scalar(0.5),
                    reversesSense: true,
                    trimSide: .towardEnd
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: .entity(setup.secondLineID),
                    parameter: .scalar(0.25),
                    trimSide: .towardStart
                ),
                continuity: .g1,
                trimsSourceCurves: true
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let updateResult) = updateResponse else {
        #expect(Bool(false))
        return
    }
    let updatedSketch = try #require(agentSketchFeature(in: session.document, featureID: setup.featureID))
    let updatedSource = try #require(session.document.productMetadata.bridgeCurveSources[source.id])
    let updatedEntity = try #require(updatedSketch.entities[bridgeID])
    guard case .spline(let updatedSpline) = updatedEntity else {
        #expect(Bool(false))
        return
    }
    let updatedControlPoints = try updatedSpline.controlPoints.map { point in
        try agentResolvedSketchPoint(point, in: session.document)
    }

    #expect(updateResult.commandName == "setBridgeCurveParameters")
    #expect(updateResult.didMutate)
    #expect(updateResult.generation == DocumentGeneration(2))
    #expect(updatedSketch.entities.count == 3)
    #expect(updatedSource.entityID == bridgeID)
    #expect(updatedSource.trimsSourceCurves)
    #expect(updatedSource.firstEndpoint.reference == .lineStart(setup.firstLineID))
    #expect(updatedSource.firstEndpoint.parameter == nil)
    #expect(updatedSource.firstEndpoint.reversesSense == false)
    #expect(updatedSource.firstEndpoint.trimSide == .towardEnd)
    #expect(updatedSource.secondEndpoint.reference == .lineEnd(setup.secondLineID))
    #expect(updatedSource.secondEndpoint.parameter == nil)
    #expect(updatedSource.secondEndpoint.trimSide == .towardStart)
    #expect(updatedSource.continuity == .g1)
    #expect(updatedSketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineStart(setup.firstLineID)
    )))
    #expect(updatedSketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineEnd(setup.secondLineID)
    )))
    #expect(updatedSketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .start,
        line: setup.firstLineID
    )))
    #expect(updatedSketch.constraints.contains(.splineEndpointTangent(
        spline: bridgeID,
        endpoint: .end,
        line: setup.secondLineID
    )))
    #expect(updatedControlPoints.count == 7)
    #expect(nearlyEqualAgent(updatedControlPoints[0].x, 0.0025))
    #expect(nearlyEqualAgent(updatedControlPoints[0].y, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[1].x, 0.001182384266129633))
    #expect(nearlyEqualAgent(updatedControlPoints[1].y, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[2].x, 0.0016666666666666668))
    #expect(nearlyEqualAgent(updatedControlPoints[2].y, 0.0025))
    #expect(nearlyEqualAgent(updatedControlPoints[3].x, 0.00125))
    #expect(nearlyEqualAgent(updatedControlPoints[3].y, 0.00375))
    #expect(nearlyEqualAgent(updatedControlPoints[4].x, 0.0008333333333333334))
    #expect(nearlyEqualAgent(updatedControlPoints[4].y, 0.005))
    #expect(nearlyEqualAgent(updatedControlPoints[5].x, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[5].y, 0.008817615733870367))
    #expect(nearlyEqualAgent(updatedControlPoints[6].x, 0.0))
    #expect(nearlyEqualAgent(updatedControlPoints[6].y, 0.0075))
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesSketchEntityEditCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Editable Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
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
            command: .setSketchArcParameters(
                target: target,
                center: nil,
                radius: .length(6.0, .millimeter),
                startAngle: nil,
                endAngle: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityKind == "arc" })
    #expect(result.commandName == "setSketchArcParameters")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.radius ?? -1.0) - 0.006) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (Double.pi * 2.0 / 3.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchEntityDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Dimensioned Line",
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
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchArcAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Angle Dimensioned Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
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
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (10.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (130.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsFixedEndSketchArcAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Fixed End Span Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(10.0, .degree),
            endAngle: .angle(80.0, .degree)
        )
    )
    let createdSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let createdArc = try #require(createdSummary.entries.first { $0.entityKind == "arc" })
    let featureID = try #require(UUID(uuidString: createdArc.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: createdArc.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.arcEnd(entityID))
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
    let arc = try #require(summary.entries.first { $0.entityID == createdArc.entityID })
    let target = try #require(arc.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(120.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedArc = try #require(updatedSummary.entries.first { $0.entityID == arc.entityID })
    let dimension = try #require(updatedArc.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedArc.startAngle ?? -1.0) - (-40.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs((updatedArc.endAngle ?? -1.0) - (80.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (120.0 * Double.pi / 180.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsSketchLineAngleDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Angled Line",
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
            command: .setSketchEntityDimension(
                target: target,
                kind: .angle,
                value: .angle(90.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "angle" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((updatedLine.end?.y ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - (Double.pi / 2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsFixedEndLineDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Fixed End Line",
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
    let createdSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(createdSummary.entries.first { $0.entityKind == "line" })
    let featureID = try #require(UUID(uuidString: line.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: line.entityID)).sketchEntityID
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .fixed(.lineEnd(entityID))
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
    let fixedLine = try #require(summary.entries.first { $0.entityID == line.entityID })
    let target = try #require(fixedLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSketchEntityDimension(
                target: target,
                kind: .length,
                value: .length(25.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedLine = try #require(updatedSummary.entries.first { $0.entityID == line.entityID })
    let dimension = try #require(updatedLine.dimensions.first { $0.kind == "distance" })
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(abs((updatedLine.start?.x ?? -1.0) - (-0.015)) < 1.0e-12)
    #expect(abs((updatedLine.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentCreatesAndMovesSplineControlPointThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(2.0, .millimeter), y: .length(4.0, .millimeter)),
                    SketchPoint(x: .length(6.0, .millimeter), y: .length(4.0, .millimeter)),
                    SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

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
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    #expect(spline.controlPoints.count == 4)

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 1,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let moveResult) = moveResponse else {
        Issue.record("Agent must return a spline edit command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityKind == "spline" })

    #expect(moveResult.commandName == "moveSketchSplineControlPoint")
    #expect(moveResult.didMutate)
    #expect(moveResult.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[1].x - 0.003) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.004) < 1.0e-12)

    let insertResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .insertSketchSplineControlPoint(
                target: target,
                fraction: .scalar(0.5)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let insertResult) = insertResponse else {
        Issue.record("Agent must return a spline control-point insertion command result.")
        return
    }
    let insertedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let insertedSpline = try #require(insertedSummary.entries.first { $0.entityKind == "spline" })
    #expect(insertResult.commandName == "insertSketchSplineControlPoint")
    #expect(insertResult.didMutate)
    #expect(insertResult.generation == DocumentGeneration(3))
    #expect(insertedSpline.controlPoints.count == 7)

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .points(controlPointCount: 4)
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve rebuild command result.")
        return
    }
    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityKind == "spline" })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(4))
    #expect(rebuiltSpline.entityID == insertedSpline.entityID)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentRefitsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Refit Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(1.0, .millimeter), y: .length(1.0, .millimeter)),
                    SketchPoint(x: .length(2.0, .millimeter), y: .length(1.0, .millimeter)),
                    SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(4.0, .millimeter), y: .length(-1.0, .millimeter)),
                    SketchPoint(x: .length(6.0, .millimeter), y: .length(-1.0, .millimeter)),
                    SketchPoint(x: .length(7.0, .millimeter), y: .length(0.0, .millimeter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

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
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .refit(
                    tolerance: .length(20.0, .millimeter),
                    keepsCorners: false
                )
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve refit command result.")
        return
    }

    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityID == spline.entityID })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(2))
    let report = try #require(rebuildResult.curveRebuildReport)
    #expect(report.method == .refit)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == 7)
    #expect(report.rebuiltControlPointCount == 4)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 1)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters >= report.rootMeanSquareDeviationMeters)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(abs((rebuiltSpline.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuiltSpline.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentExplicitlyRebuildsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Explicit Rebuild Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(1.0, .millimeter), y: .length(2.0, .millimeter)),
                    SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                    SketchPoint(x: .length(3.0, .millimeter), y: .length(0.0, .millimeter)),
                    SketchPoint(x: .length(4.0, .millimeter), y: .length(-3.0, .millimeter)),
                    SketchPoint(x: .length(6.0, .millimeter), y: .length(-3.0, .millimeter)),
                    SketchPoint(x: .length(7.0, .millimeter), y: .length(0.0, .millimeter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must return a spline creation command result.")
        return
    }
    #expect(createResult.commandName == "createSplineSketch")
    #expect(createResult.generation == DocumentGeneration(1))

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
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())

    let rebuildResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .rebuildSketchCurve(
                target: target,
                options: .explicitControl(
                    degree: 3,
                    spanCount: 1,
                    weight: 0.5
                )
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let rebuildResult) = rebuildResponse else {
        Issue.record("Agent must return a sketch curve Explicit Control command result.")
        return
    }

    let rebuiltSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let rebuiltSpline = try #require(rebuiltSummary.entries.first { $0.entityID == spline.entityID })
    #expect(rebuildResult.commandName == "rebuildSketchCurve")
    #expect(rebuildResult.didMutate)
    #expect(rebuildResult.generation == DocumentGeneration(2))
    let report = try #require(rebuildResult.curveRebuildReport)
    #expect(report.method == .explicitControl)
    #expect(report.sourceFeatureID == spline.sourceFeatureID)
    #expect(report.entityID == spline.entityID)
    #expect(report.originalControlPointCount == 7)
    #expect(report.rebuiltControlPointCount == 4)
    #expect(report.originalSpanCount == 2)
    #expect(report.rebuiltSpanCount == 1)
    #expect(report.deviationMeasurement == .analyticCubicBezier)
    #expect(report.evaluatedIntervalCount == 2)
    #expect(report.criticalPointCount >= 0)
    #expect(report.maximumDeviationMeters >= report.rootMeanSquareDeviationMeters)
    #expect(rebuiltSpline.controlPoints.count == 4)
    #expect(abs((rebuiltSpline.controlPoints.first?.x ?? -1.0) - 0.000) < 1.0e-12)
    #expect(abs((rebuiltSpline.controlPoints.last?.x ?? -1.0) - 0.007) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentExtrudesClosedSplineProfileThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Spline Profile",
                plane: .xy,
                spline: agentClosedBezierCircleSpline(radius: 0.01)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let createResult) = createResponse else {
        Issue.record("Agent must create a closed spline profile.")
        return
    }
    let sketchFeatureID = try #require(session.document.cadDocument.designGraph.order.first)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Spline Body",
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .length(0.005, .meter),
                direction: .normal
            ),
            expectedGeneration: createResult.generation
        )
    )
    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must extrude the closed spline profile.")
        return
    }

    #expect(createResult.commandName == "createSplineSketch")
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
}
