import Testing
import Darwin
import Foundation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentDimensionExpressionDefaultsFollowDocumentDisplayUnitWhenOmitted() async throws {
    var document = DesignDocument.empty(named: "Agent Scale Expression Defaults")
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    let lineFeatureID = try document.createLineSketch(
        name: "Agent Site Line",
        plane: .xy,
        start: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        end: SketchPoint(
            x: .length(10.0, .meter),
            y: .length(0.0, .meter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let createBodyResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Site Box",
                plane: .xy,
                width: .length(1.0, .meter),
                height: .length(1.0, .meter),
                depth: .length(1.0, .meter),
                direction: .normal
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command = createBodyResponse else {
        Issue.record("Agent must create a body before editing object dimensions.")
        return
    }
    let bodyNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    let parameterResponse = server.handle(
        .setParameterExpression(
            sessionID: sessionID,
            name: "siteWidth",
            expression: "12",
            kind: .length,
            defaults: nil,
            expectedGeneration: session.generation
        )
    )
    guard case .command = parameterResponse else {
        Issue.record("Agent must accept omitted expression defaults.")
        return
    }
    let parameter = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "siteWidth"
    })
    let resolvedParameter = try session.document.cadDocument.parameters.resolvedValue(for: parameter.expression)
    #expect(resolvedParameter.kind == .length)
    #expect(abs(resolvedParameter.value - 12_000.0) <= 1.0e-9)

    let objectDimensionResponse = server.handle(
        .setObjectDimensionExpression(
            sessionID: sessionID,
            target: SelectionTarget(sceneNodeID: bodyNode.id),
            kind: .sizeX,
            expression: "6",
            defaults: nil,
            expectedGeneration: session.generation
        )
    )
    guard case .command(let objectDimensionResult) = objectDimensionResponse else {
        Issue.record("Agent must edit object dimensions with omitted defaults.")
        return
    }
    #expect(objectDimensionResult.commandName == "setObjectDimension")
    let editedBodyNode = try #require(session.document.productMetadata.sceneNodes[bodyNode.id])
    guard case .length(let sizeX)? = editedBodyNode.object?.properties["size.x"] else {
        Issue.record("Expected a body size X property.")
        return
    }
    #expect(abs(sizeX - 6_000.0) <= 1.0e-9)

    let lineTarget = try agentLineCurveTarget(in: session.document, featureID: lineFeatureID)
    let sketchDimensionResponse = server.handle(
        .setSketchEntityDimensionExpression(
            sessionID: sessionID,
            target: lineTarget,
            kind: .length,
            expression: "4",
            defaults: nil,
            expectedGeneration: session.generation
        )
    )
    guard case .command(let sketchDimensionResult) = sketchDimensionResponse else {
        Issue.record("Agent must edit sketch dimensions with omitted defaults.")
        return
    }
    #expect(sketchDimensionResult.commandName == "setSketchEntityDimension")
    let lengthEndpoints = try agentLineEndpoints(in: session.document, featureID: lineFeatureID)
    let resolvedLineLength = hypot(
        lengthEndpoints.end.x - lengthEndpoints.start.x,
        lengthEndpoints.end.y - lengthEndpoints.start.y
    )
    #expect(abs(resolvedLineLength - 4_000.0) <= 1.0e-9)

    let endpointTargets = try agentLineEndpointTargets(in: session.document, featureID: lineFeatureID)
    let addDimensionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSelectionDimension(
                name: "Agent Site Span",
                kind: .distance,
                first: endpointTargets.start,
                second: endpointTargets.end,
                target: .length(4.0, .meter)
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let addDimensionResult) = addDimensionResponse,
          let dimensionID = addDimensionResult.addedSelectionDimensionID else {
        Issue.record("Agent must create a selection dimension.")
        return
    }

    let targetResponse = server.handle(
        .setSelectionDimensionTargetExpression(
            sessionID: sessionID,
            id: dimensionID,
            expression: "3",
            defaults: nil,
            expectedGeneration: session.generation
        )
    )
    guard case .command(let targetResult) = targetResponse else {
        Issue.record("Agent must edit selection dimensions with omitted defaults.")
        return
    }
    #expect(targetResult.commandName == "setSelectionDimensionTarget")
    let dimension = try #require(
        session.document.cadDocument.selectionDimensions.first { $0.id == dimensionID }
    )
    let quantity = try session.document.cadDocument.parameters.resolvedValue(for: dimension.target)
    #expect(quantity.kind == .length)
    #expect(abs(quantity.value - 3_000.0) <= 1.0e-9)
}

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
