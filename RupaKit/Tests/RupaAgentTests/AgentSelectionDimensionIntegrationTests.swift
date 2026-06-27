import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentAddsAndEvaluatesPersistentSelectionDimension() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(16.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let targets = try agentLineEndpointTargets(in: document, featureID: featureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Length",
                kind: .distance,
                first: targets.start,
                second: targets.end,
                target: .length(16.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)
    #expect(addResult.commandName == "addSelectionDimension")
    #expect(addResult.didMutate)
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.document.productMetadata.measurements.isEmpty)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(measurement.measured == .length(0.016, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(12.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)
    #expect(setResult.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.selectionDimensions.first?.target == .length(12.0, .millimeter))

    let updatedEvaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .selectionDimensionEvaluation(let updatedEvaluation) = updatedEvaluationResponse else {
        #expect(Bool(false))
        return
    }
    let updatedMeasurement = try #require(updatedEvaluation.measurements.first)
    #expect(updatedMeasurement.measured == .length(0.016, unit: .meter))
    #expect(updatedMeasurement.target == .length(0.012, unit: .meter))
    #expect(abs(updatedMeasurement.residual.value - 0.004) <= 1.0e-12)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)
    #expect(applyResult.generation == DocumentGeneration(3))

    let appliedEvaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )

    guard case .selectionDimensionEvaluation(let appliedEvaluation) = appliedEvaluationResponse else {
        #expect(Bool(false))
        return
    }
    let appliedMeasurement = try #require(appliedEvaluation.measurements.first)
    #expect(appliedMeasurement.measured == .length(0.012, unit: .meter))
    #expect(appliedMeasurement.target == .length(0.012, unit: .meter))
    #expect(abs(appliedMeasurement.residual.value) <= 1.0e-12)

    let removeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .removeSelectionDimension(id: dimensionID),
            expectedGeneration: DocumentGeneration(3)
        )
    )

    guard case .command(let removeResult) = removeResponse else {
        #expect(Bool(false))
        return
    }
    #expect(removeResult.commandName == "removeSelectionDimension")
    #expect(removeResult.didMutate)
    #expect(removeResult.generation == DocumentGeneration(4))
    #expect(session.document.cadDocument.selectionDimensions.isEmpty)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToSourcePointDistance() async throws {
    var document = DesignDocument.empty()
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Anchor Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let editableFeatureID = try document.createLineSketch(
        name: "Agent Editable Point Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let editableTargets = try agentLineEndpointTargets(in: document, featureID: editableFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Point Distance",
                kind: .distance,
                first: editableTargets.start,
                second: anchorTargets.start,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let editableEndpoints = try agentLineEndpoints(
        in: session.document,
        featureID: editableFeatureID
    )

    #expect(abs(editableEndpoints.start.x - 0.006) <= 1.0e-12)
    #expect(abs(editableEndpoints.start.y) <= 1.0e-12)
    #expect(abs(editableEndpoints.end.x - 0.010) <= 1.0e-12)
    #expect(abs(editableEndpoints.end.y - 0.010) <= 1.0e-12)
    #expect(measurement.measured == .length(0.006, unit: .meter))
    #expect(measurement.target == .length(0.006, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToArcEndpointDistance() async throws {
    var document = DesignDocument.empty()
    let arcFeatureID = try document.createArcSketch(
        name: "Agent Arc Endpoint",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter),
        startAngle: .angle(0.0, .degree),
        endAngle: .angle(90.0, .degree)
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Arc Anchor",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(6.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let arcTargets = try agentArcEndpointTargets(in: document, featureID: arcFeatureID)
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Arc Endpoint Distance",
                kind: .distance,
                first: arcTargets.start,
                second: anchorTargets.start,
                target: .length(sqrt(72.0), .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)

    #expect(abs(try agentArcStartAngle(in: session.document, featureID: arcFeatureID) - Double.pi / 6.0) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToStandaloneSketchPointDistance() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createAgentStandalonePointSketch(
        in: &document,
        name: "Agent Editable Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(0.0, .millimeter)
        )
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Point Anchor",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let pointTarget = try agentStandalonePointTarget(in: document, featureID: pointFeatureID)
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Standalone Point Distance",
                kind: .distance,
                first: pointTarget,
                second: anchorTargets.start,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let movedPoint = try agentStandalonePoint(in: session.document, featureID: pointFeatureID)

    #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(movedPoint.y) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    guard case .sketchPoint(let point) = measurement.dimension.first else {
        Issue.record("Expected standalone point selection reference")
        return
    }
    #expect(point.featureID == pointFeatureID)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToStandalonePointWholeLineDistance() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createAgentStandalonePointSketch(
        in: &document,
        name: "Agent Editable Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )
    let lineFeatureID = try document.createLineSketch(
        name: "Agent Reference Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let pointTarget = try agentStandalonePointTarget(in: document, featureID: pointFeatureID)
    let lineTarget = try agentLineCurveTarget(in: document, featureID: lineFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Point To Line Distance",
                kind: .distance,
                first: pointTarget,
                second: lineTarget,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let movedPoint = try agentStandalonePoint(in: session.document, featureID: pointFeatureID)

    #expect(abs(movedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(movedPoint.y - 0.005) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    guard case .sketchPoint(let point) = measurement.dimension.first,
          case .curve(.whole(let line)) = measurement.dimension.second else {
        Issue.record("Expected standalone point to whole line selection references")
        return
    }
    #expect(point.featureID == pointFeatureID)
    #expect(line.featureID == lineFeatureID)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetByTranslatingLineWhenPointIsFixed() async throws {
    var document = DesignDocument.empty()
    let pointFeatureID = try createAgentStandalonePointSketch(
        in: &document,
        name: "Agent Fixed Point",
        plane: .xy,
        point: SketchPoint(
            x: .length(10.0, .millimeter),
            y: .length(5.0, .millimeter)
        )
    )
    let lineFeatureID = try document.createLineSketch(
        name: "Agent Movable Reference Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let pointEntityID = try agentStandalonePointEntityID(in: document, featureID: pointFeatureID)
    try document.addSketchConstraint(
        featureID: pointFeatureID,
        constraint: .fixed(.entity(pointEntityID))
    )
    let pointTarget = try agentStandalonePointTarget(in: document, featureID: pointFeatureID)
    let lineTarget = try agentLineCurveTarget(in: document, featureID: lineFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Fixed Point To Line Distance",
                kind: .distance,
                first: pointTarget,
                second: lineTarget,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let fixedPoint = try agentStandalonePoint(in: session.document, featureID: pointFeatureID)
    let movedLine = try agentLineEndpoints(in: session.document, featureID: lineFeatureID)

    #expect(abs(fixedPoint.x - 0.010) <= 1.0e-12)
    #expect(abs(fixedPoint.y - 0.005) <= 1.0e-12)
    #expect(abs(movedLine.start.x - 0.004) <= 1.0e-12)
    #expect(abs(movedLine.start.y) <= 1.0e-12)
    #expect(abs(movedLine.end.x - 0.004) <= 1.0e-12)
    #expect(abs(movedLine.end.y - 0.010) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
    guard case .sketchPoint(let point) = measurement.dimension.first,
          case .curve(.whole(let line)) = measurement.dimension.second else {
        Issue.record("Expected standalone point to whole line selection references")
        return
    }
    #expect(point.featureID == pointFeatureID)
    #expect(line.featureID == lineFeatureID)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToSplineControlPointDistance() async throws {
    var document = DesignDocument.empty()
    let splineFeatureID = try document.createSplineSketch(
        name: "Agent Editable Spline",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            SketchPoint(x: .length(12.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(14.0, .millimeter), y: .length(3.0, .millimeter)),
            SketchPoint(x: .length(16.0, .millimeter), y: .length(0.0, .millimeter)),
        ])
    )
    let anchorFeatureID = try document.createLineSketch(
        name: "Agent Spline Anchor",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let splineTargets = try agentSplineControlPointTargets(in: document, featureID: splineFeatureID)
    let anchorTargets = try agentLineEndpointTargets(in: document, featureID: anchorFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Spline CV Distance",
                kind: .distance,
                first: splineTargets[0],
                second: anchorTargets.start,
                target: .length(10.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    let controlPoints = try agentSplineControlPoints(
        in: session.document,
        featureID: splineFeatureID
    )

    #expect(abs(controlPoints[0].x - 0.006) <= 1.0e-12)
    #expect(abs(controlPoints[0].y) <= 1.0e-12)
    #expect(abs(controlPoints[1].x - 0.012) <= 1.0e-12)
    #expect(abs(controlPoints[1].y - 0.003) <= 1.0e-12)
    assertAgentLengthQuantity(measurement.measured, equals: 0.006)
    assertAgentLengthQuantity(measurement.target, equals: 0.006)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToCircleRadius() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: "Agent Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(6.0, .millimeter)
    )
    let targets = try agentCircleCenterAndCurveTargets(in: document, featureID: featureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Radius",
                kind: .distance,
                first: targets.center,
                second: targets.curve,
                target: .length(6.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(4.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(abs(try agentCircleRadius(in: session.document, featureID: featureID) - 0.004) <= 1.0e-12)
    #expect(measurement.measured == .length(0.004, unit: .meter))
    #expect(measurement.target == .length(0.004, unit: .meter))
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesSelectionDimensionTargetToLineRelativeAngle() async throws {
    var document = DesignDocument.empty()
    let referenceFeatureID = try document.createLineSketch(
        name: "Agent Reference Line",
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
    let editableFeatureID = try document.createLineSketch(
        name: "Agent Editable Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(10.0, .millimeter)
        )
    )
    let reference = try agentLineCurveTarget(in: document, featureID: referenceFeatureID)
    let editable = try agentLineCurveTarget(in: document, featureID: editableFeatureID)
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Relative Angle",
                kind: .angle,
                first: editable,
                second: reference,
                target: .angle(90.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .angle(45.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(abs(try agentLineAngle(in: session.document, featureID: editableFeatureID) - Double.pi / 4.0) <= 1.0e-12)
    assertAgentAngleQuantity(measurement.measured, equals: Double.pi / 4.0)
    assertAgentAngleQuantity(measurement.target, equals: Double.pi / 4.0)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAddsAndEvaluatesGeneratedFacePairSelectionDimension() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let facePair = try agentParallelFaceDimensionTargets(in: topology)

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Face Distance",
                kind: .distance,
                first: facePair.first,
                second: facePair.second,
                target: .length(facePair.distance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)
    #expect(addResult.commandName == "addSelectionDimension")
    #expect(addResult.didMutate)
    #expect(session.document.cadDocument.selectionDimensions.map(\.id) == [dimensionID])
    #expect(session.document.productMetadata.measurements.isEmpty)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: session.generation
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    #expect(evaluation.measurements.count == 1)
    #expect(measurement.dimension.id == dimensionID)
    #expect(abs(measurement.measured.value - facePair.distance) <= 1.0e-12)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}

@MainActor
@Test func agentAppliesGeneratedFacePairSelectionDimensionTarget() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: session.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        #expect(Bool(false))
        return
    }
    let facePair = try agentParallelFaceDimensionTargets(in: topology)
    let targetDistance = facePair.distance + 0.004

    let addResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Editable Face Distance",
                kind: .distance,
                first: facePair.first,
                second: facePair.second,
                target: .length(facePair.distance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let addResult) = addResponse else {
        #expect(Bool(false))
        return
    }
    let dimensionID = try #require(addResult.addedSelectionDimensionID)

    let setResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSelectionDimensionTarget(
                id: dimensionID,
                target: .length(targetDistance, .meter)
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let setResult) = setResponse else {
        #expect(Bool(false))
        return
    }
    #expect(setResult.commandName == "setSelectionDimensionTarget")
    #expect(setResult.didMutate)

    let applyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .applySelectionDimensionTarget(id: dimensionID),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let applyResult) = applyResponse else {
        #expect(Bool(false))
        return
    }
    #expect(applyResult.commandName == "applySelectionDimensionTarget")
    #expect(applyResult.didMutate)

    let evaluationResponse = server.handle(
        .selectionDimensionEvaluation(
            sessionID: sessionID,
            dimensionID: dimensionID,
            expectedGeneration: session.generation
        )
    )
    guard case .selectionDimensionEvaluation(let evaluation) = evaluationResponse else {
        #expect(Bool(false))
        return
    }
    let measurement = try #require(evaluation.measurements.first)
    assertAgentLengthQuantity(measurement.measured, equals: targetDistance)
    assertAgentLengthQuantity(measurement.target, equals: targetDistance)
    #expect(abs(measurement.residual.value) <= 1.0e-12)
}
