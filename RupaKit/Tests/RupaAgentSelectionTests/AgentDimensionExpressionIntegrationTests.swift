import Testing
import Darwin
import Foundation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentSetsObjectDimensionExpressionWithKilometerParameter() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Expression Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command = createResponse else {
        Issue.record("Agent must create a box before editing dimensions.")
        return
    }

    let parameterResponse = server.handle(
        .setParameterExpression(
            sessionID: sessionID,
            name: "siteWidth",
            expression: "1km",
            kind: .length,
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: session.generation
        )
    )
    guard case .command = parameterResponse else {
        Issue.record("Agent must accept kilometer parameter expressions.")
        return
    }
    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    let dimensionResponse = server.handle(
        .setObjectDimensionExpression(
            sessionID: sessionID,
            target: SelectionTarget(sceneNodeID: bodyNode.id),
            kind: .sizeX,
            expression: "siteWidth / 1000 + 250mm",
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = dimensionResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(result.commandName == "setObjectDimension")
    #expect(result.didMutate)
    let editedBodyNode = try #require(session.document.productMetadata.sceneNodes[bodyNode.id])
    guard case .length(let sizeX)? = editedBodyNode.object?.properties["size.x"] else {
        Issue.record("Expected a body size X property.")
        return
    }
    #expect(abs(sizeX - 1.25) <= 1.0e-12)
}

@MainActor
@Test func agentSetsSketchEntityDimensionExpressionsWithArchitecturalLengthAndAngle() async throws {
    var document = DesignDocument.empty(named: "Agent Sketch Expression")
    let featureID = try document.createLineSketch(
        name: "Agent Expression Line",
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
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)
    let lineTarget = try agentLineCurveTarget(in: session.document, featureID: featureID)

    let lengthResponse = server.handle(
        .setSketchEntityDimensionExpression(
            sessionID: sessionID,
            target: lineTarget,
            kind: .length,
            expression: "6' 4\"",
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let lengthResult) = lengthResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(lengthResult.commandName == "setSketchEntityDimension")
    let lengthEndpoints = try agentLineEndpoints(in: session.document, featureID: featureID)
    let resolvedLength = hypot(
        lengthEndpoints.end.x - lengthEndpoints.start.x,
        lengthEndpoints.end.y - lengthEndpoints.start.y
    )
    let expectedLength = LengthDisplayUnit.foot.meters(from: 6.0)
        + LengthDisplayUnit.inch.meters(from: 4.0)
    #expect(abs(resolvedLength - expectedLength) <= 1.0e-12)

    let angleResponse = server.handle(
        .setSketchEntityDimensionExpression(
            sessionID: sessionID,
            target: lineTarget,
            kind: .angle,
            expression: "45deg",
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let angleResult) = angleResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(angleResult.commandName == "setSketchEntityDimension")
    let resolvedAngle = try agentLineAngle(in: session.document, featureID: featureID)
    #expect(abs(resolvedAngle - Double.pi / 4.0) <= 1.0e-12)
}

@MainActor
@Test func agentSetsSelectionDimensionTargetExpressionFromStoredKind() async throws {
    var document = DesignDocument.empty(named: "Agent Selection Dimension Expression")
    let featureID = try document.createLineSketch(
        name: "Agent Dimension Line",
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
                name: "Agent Target",
                kind: .distance,
                first: targets.start,
                second: targets.end,
                target: .length(16.0, .millimeter)
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let addResult) = addResponse,
          let dimensionID = addResult.addedSelectionDimensionID else {
        Issue.record("Agent must create a selection dimension.")
        return
    }

    let setResponse = server.handle(
        .setSelectionDimensionTargetExpression(
            sessionID: sessionID,
            id: dimensionID,
            expression: "1.2km / 100000",
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: session.generation
        )
    )

    guard case .command(let result) = setResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    #expect(result.commandName == "setSelectionDimensionTarget")
    let dimension = try #require(
        session.document.cadDocument.selectionDimensions.first { $0.id == dimensionID }
    )
    let quantity = try session.document.cadDocument.parameters.resolvedValue(for: dimension.target)
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - 0.012) <= 1.0e-12)
}

@Test func agentMessageCodecRoundTripsDimensionExpressionRequests() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(SelectionComponentID(rawValue: "sketchEntity:test"))
    )
    let requests: [AgentRequest] = [
        .setObjectDimensionExpression(
            sessionID: sessionID,
            target: target,
            kind: .sizeX,
            expression: "1km",
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: DocumentGeneration(3)
        ),
        .setSketchEntityDimensionExpression(
            sessionID: sessionID,
            target: target,
            kind: .angle,
            expression: "45deg",
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: DocumentGeneration(3)
        ),
        .setSelectionDimensionTargetExpression(
            sessionID: sessionID,
            id: SelectionDimensionID(),
            expression: "6' 4\"",
            defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
            expectedGeneration: DocumentGeneration(3)
        ),
    ]

    for request in requests {
        #expect(try codec.decodeRequest(from: try codec.encode(request)) == request)
    }
}
