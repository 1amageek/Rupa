import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@Test func agentDispatchesCircleModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedCircle(
                name: "Agent Cylinder",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(6.0, .millimeter),
                depth: .length(10.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedCircle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@Test func agentDispatchesSketchPrimitiveCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createCircleSketch(
                name: "Agent Circle",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createCircleSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@Test func agentDispatchesCurveCurvatureDisplayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createCircleSketch(
                name: "Agent Curvature Display Circle",
                plane: .xy,
                center: SketchPoint(
                    x: .length(0.0, .millimeter),
                    y: .length(0.0, .millimeter)
                ),
                radius: .length(5.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityKind == "circle" })
    let target = try #require(circle.selectionTarget())
    let componentID = try #require(agentSketchEntityComponentID(from: target))

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setCurveCurvatureDisplay(
                target: target,
                isVisible: true,
                combScale: 0.2
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setCurveCurvatureDisplay")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.curveCurvatureDisplays[componentID]?.combScale == 0.2)
}

@Test func agentDispatchesPointDisplayCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSplineSketch(
                name: "Agent Point Display Spline",
                plane: .xy,
                spline: SketchSpline(controlPoints: [
                    SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
                    SketchPoint(x: .length(0.002, .meter), y: .length(0.004, .meter)),
                    SketchPoint(x: .length(0.006, .meter), y: .length(0.004, .meter)),
                    SketchPoint(x: .length(0.008, .meter), y: .length(0.0, .meter)),
                ])
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let componentID = try #require(agentSketchEntityComponentID(from: target))

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setPointDisplay(
                target: target,
                isVisible: false
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "setPointDisplay")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.productMetadata.pointDisplays[componentID]?.isVisible == false)
}

@Test func agentDispatchesPolygonSketchCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createPolygonSketch(
                name: "Agent Polygon",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter),
                sides: 5,
                sizingMode: .inradius,
                inclinationMode: .vertical,
                rotationAngle: .angle(0.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createPolygonSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sketch.entities.count == 5)
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    let polygonNode = try #require(session.document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    #expect(polygonNode.object?.properties["radius.is.inradius"] == .boolean(true))
    #expect(polygonNode.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.vertical.rawValue))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@Test func agentDispatchesArcSketchCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createArcSketch(
                name: "Agent Arc",
                plane: .xy,
                center: SketchPoint(
                    x: .length(2.0, .millimeter),
                    y: .length(3.0, .millimeter)
                ),
                radius: .length(4.0, .millimeter),
                startAngle: .angle(0.0, .degree),
                endAngle: .angle(135.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        #expect(Bool(false))
        return
    }
    let entity = try #require(sketch.entities.values.first)
    guard case .arc = entity else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createArcSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 0)
}

@MainActor
@Test func agentDispatchesSketchConstraintCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Constraint Source",
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
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(agentSingleSketchEntityID(in: session.document, featureID: featureID))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .horizontal(lineID)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: featureID))
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let line = try #require(summary.entries.first { $0.entityID == lineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
    #expect(abs((line.start?.x ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((line.start?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(abs((line.end?.x ?? -1.0) - 0.010) < 1.0e-12)
    #expect(abs((line.end?.y ?? -1.0) - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@Test func agentDispatchesSketchConstraintRemovalCommandThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Constraint Removal Source",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(8.0, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.first)
    let lineID = try #require(agentSingleSketchEntityID(in: session.document, featureID: featureID))
    _ = try session.execute(
        .addSketchConstraint(
            featureID: featureID,
            constraint: .horizontal(lineID)
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .removeSketchConstraint(
                featureID: featureID,
                constraint: .horizontal(lineID)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let sketch = try #require(agentSketchFeature(in: session.document, featureID: featureID))
    #expect(result.commandName == "removeSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(sketch.constraints.isEmpty)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesFixedSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Fixed Spline Point",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .fixed(.splineControlPoint(entity: entityID, index: 0))
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))

    let moveResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchSplineControlPoint(
                target: target,
                controlPointIndex: 0,
                deltaX: .length(1.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .failure(let error) = moveResponse else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .commandInvalid)
    #expect(error.message == "Sketch spline control point move cannot move a fixed sketch point.")
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSlideSketchSplineControlPointsThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Slide CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let target = try #require(spline.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .slideSketchSplineControlPoints(
                target: target,
                controlPointIndexes: [1, 2],
                direction: .normal,
                distance: .length(1.5, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    #expect(result.commandName == "slideSketchSplineControlPoints")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(updatedSpline.controlPoints[1].x - 0.002) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[1].y - 0.0015) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].x - 0.006) < 1.0e-12)
    #expect(abs(updatedSpline.controlPoints[2].y - 0.0015) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesCoincidentSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSplinePointConstraintDocument(name: "Agent Coincident Spline Point")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .coincident(
                    .splineControlPoint(entity: setup.splineID, index: 0),
                    .entity(setup.pointID)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        #expect(Bool(false))
        return
    }
    let point = try #require(summary.entries.first { $0.entityID == setup.pointID.description })
    let center = try #require(point.center)
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(center.x - 0.0) < 1.0e-12)
    #expect(abs(center.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSmoothSplineControlPointConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Smooth Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(1.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(4.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(1.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityKind == "spline" })
    let featureID = try #require(UUID(uuidString: spline.sourceFeatureID)).featureID
    let entityID = try #require(UUID(uuidString: spline.entityID)).sketchEntityID
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: featureID,
                constraint: .smoothSplineControlPoint(entity: entityID, index: 3)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let updatedSpline = try #require(updatedSummary.entries.first { $0.entityID == spline.entityID })
    let outgoingHandle = try #require(updatedSpline.controlPoints.dropFirst(4).first)
    let constraint = try #require(updatedSpline.constraints.first { $0.kind == "smoothSplineControlPoint" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(constraint.references == ["splineControlPoint:\(entityID.description):3"])
    #expect(abs(outgoingHandle.x - 0.005) < 1.0e-12)
    #expect(abs(outgoingHandle.y - (-0.001)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSplineEndpointTangentConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentSplineLineTangentSketchDocument(name: "Agent Spline Tangency")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .splineEndpointTangent(
                    spline: setup.splineID,
                    endpoint: .start,
                    line: setup.lineID
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let spline = try #require(summary.entries.first { $0.entityID == setup.splineID.description })
    let alignedHandle = try #require(spline.controlPoints.dropFirst(1).first)
    let constraint = try #require(spline.constraints.first { $0.kind == "splineEndpointTangent" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.splineID.description):start",
        "entity:\(setup.lineID.description)",
    ])
    #expect(abs(alignedHandle.x - 0.005) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesTangentSplineEndpointsConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoSplineTangentSketchDocument(name: "Agent Spline Endpoint Tangency")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .tangentSplineEndpoints(
                    first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(summary.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "tangentSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentDispatchesSmoothSplineEndpointsConstraintThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoSplineTangentSketchDocument(name: "Agent Spline Endpoint Smoothness")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .smoothSplineEndpoints(
                    first: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
                    second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start)
                )
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let secondSpline = try #require(summary.entries.first { $0.entityID == setup.secondSplineID.description })
    let alignedEndpoint = try #require(secondSpline.controlPoints.first)
    let alignedHandle = try #require(secondSpline.controlPoints.dropFirst(1).first)
    let constraint = try #require(secondSpline.constraints.first { $0.kind == "smoothSplineEndpoints" })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(constraint.references == [
        "splineEndpoint:\(setup.firstSplineID.description):end",
        "splineEndpoint:\(setup.secondSplineID.description):start",
    ])
    #expect(abs(alignedEndpoint.x - 0.009) < 1.0e-12)
    #expect(abs(alignedEndpoint.y - 0.0) < 1.0e-12)
    #expect(abs(alignedHandle.x - 0.012) < 1.0e-12)
    #expect(abs(alignedHandle.y - 0.0) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsParallelConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Parallel Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .parallel(setup.firstLineID, setup.secondLineID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(agentLineEntriesAreParallel(first, second))
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsEqualLengthConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineUnconstrainedSketchDocument(name: "Agent Equal Length Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .equalLength(setup.firstLineID, setup.secondLineID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondLineID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs(agentLineEntryLength(first) - agentLineEntryLength(second)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsTangentConstraintAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineCircleTangentSketchDocument(name: "Agent Tangent Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .tangent(setup.lineID, setup.circleID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a command result.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let circle = try #require(summary.entries.first { $0.entityID == setup.circleID.description })
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(abs((circle.center?.x ?? -1.0) - 0.005) < 1.0e-12)
    #expect(abs((circle.center?.y ?? -1.0) - (circle.radius ?? -2.0)) < 1.0e-12)
    #expect(abs((circle.radius ?? -1.0) - 0.002) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentAddsCircularConstraintsAndCoreSatisfiesGeometry() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoCircleSketchDocument(name: "Agent Circular Constraint Source")
    let session = EditorSession(document: setup.document)
    server.register(session: session, id: sessionID)

    let concentricResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .concentric(setup.firstCircleID, setup.secondCircleID)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    let radiusResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .addSketchConstraint(
                featureID: setup.featureID,
                constraint: .equalRadius(setup.firstCircleID, setup.secondCircleID)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let concentricResult) = concentricResponse,
          case .command(let radiusResult) = radiusResponse else {
        Issue.record("Agent must return command results.")
        return
    }
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let first = try #require(summary.entries.first { $0.entityID == setup.firstCircleID.description })
    let second = try #require(summary.entries.first { $0.entityID == setup.secondCircleID.description })
    #expect(concentricResult.commandName == "addSketchConstraint")
    #expect(radiusResult.commandName == "addSketchConstraint")
    #expect(concentricResult.didMutate)
    #expect(radiusResult.didMutate)
    #expect(abs((first.center?.x ?? -1.0) - (second.center?.x ?? -2.0)) < 1.0e-12)
    #expect(abs((first.center?.y ?? -1.0) - (second.center?.y ?? -2.0)) < 1.0e-12)
    #expect(abs((first.radius ?? -1.0) - (second.radius ?? -2.0)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}
