import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentCreatesSweepSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Agent Sweep Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Agent Sweep Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Sweep",
                sections: [.profile(ProfileReference(featureID: profileID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions()
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])
    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Agent must create a sweep feature.")
        return
    }

    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sweep.sections == [.profile(ProfileReference(featureID: profileID))])
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentReturnsSweepEvaluationPlanWithoutMutatingDocument() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Agent Sweep Plan Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let pathID = try document.createLineSketch(
        name: "Agent Sweep Plan Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)
    let initialGeneration = session.generation
    let initialFeatureOrder = session.document.cadDocument.designGraph.order

    let response = server.handle(
        .sweepEvaluationPlan(
            sessionID: sessionID,
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [],
            targets: [],
            options: SweepOptions(),
            expectedGeneration: initialGeneration
        )
    )

    guard case .sweepEvaluationPlan(let plan) = response else {
        Issue.record("Agent must return a sweep evaluation plan.")
        return
    }

    #expect(plan.status == .supported)
    #expect(plan.evaluationKind == .exactStraightExtrude)
    #expect(plan.outputTopologyKind == .exactStraightSolid)
    #expect(plan.booleanSupportKind == .newBody)
    #expect(plan.guideStrategyCandidates == [.none])
    #expect(plan.resolvedGuideStrategy == nil)
    #expect(plan.guideStrategyResolutions == [
        SweepGuideStrategyResolution(
            strategy: .none,
            status: .notRequired,
            message: "Sweep has no guide constraints."
        ),
    ])
    #expect(plan.checks.last?.kind == .capabilityDecision)
    #expect(plan.checks.last?.status == .passed)
    #expect(session.generation == initialGeneration)
    #expect(session.document.cadDocument.designGraph.order == initialFeatureOrder)
}

@MainActor
@Test func agentReturnsGuidedSweepEvaluationPlanWithResolvedGuideStrategy() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Agent Guided Sweep Plan Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(4.0, .millimeter),
            y: .length(2.0, .millimeter)
        )
    )
    let pathID = try document.createLineSketch(
        name: "Agent Guided Sweep Plan Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let guideID = try document.createLineSketch(
        name: "Agent Guided Sweep Plan Guide",
        plane: .yz,
        start: SketchPoint(
            x: .length(2.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(2.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)
    let initialGeneration = session.generation
    let initialFeatureOrder = session.document.cadDocument.designGraph.order

    let response = server.handle(
        .sweepEvaluationPlan(
            sessionID: sessionID,
            sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            guides: [SweepGuideReference(featureID: guideID)],
            targets: [],
            options: SweepOptions(guideMethod: .point),
            expectedGeneration: initialGeneration
        )
    )

    guard case .sweepEvaluationPlan(let plan) = response else {
        Issue.record("Agent must return a guided sweep evaluation plan.")
        return
    }

    #expect(plan.status == .supported)
    #expect(plan.sectionState == .guided)
    #expect(plan.guideCount == 1)
    #expect(plan.guideStrategyCandidates == [.pointSimilarity])
    #expect(plan.resolvedGuideStrategy == .pointSimilarity)
    #expect(plan.guideStrategyResolutions == [
        SweepGuideStrategyResolution(
            strategy: .pointSimilarity,
            status: .resolved,
            message: "Sweep guide constraints solve as pointSimilarity."
        ),
    ])
    #expect(plan.checks.contains {
        $0.kind == .guideConstraints &&
            $0.status == .passed &&
            $0.message.contains("pointSimilarity")
    })
    #expect(session.generation == initialGeneration)
    #expect(session.document.cadDocument.designGraph.order == initialFeatureOrder)
}

@MainActor
@Test func agentCreatesCurveSectionSheetSweepThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let sectionID = try document.createLineSketch(
        name: "Agent Curve Sheet Section",
        plane: .xy,
        start: agentSketchPoint(x: -0.002, y: 0.0),
        end: agentSketchPoint(x: 0.002, y: 0.0)
    )
    let pathID = try document.createLineSketch(
        name: "Agent Curve Sheet Path",
        plane: .yz,
        start: agentSketchPoint(x: 0.0, y: 0.0),
        end: agentSketchPoint(x: 0.0, y: 0.020)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Curve Sheet Sweep",
                sections: [.curve(SweepCurveSectionReference(featureID: sectionID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions(resultKind: .sheet)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a curve-section sheet sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])
    let evaluated = try CADPipeline.modelingDefault(for: session.document).evaluate(
        session.document.cadDocument
    )
    let body = try #require(evaluated.brep.bodies.values.first)

    guard case .sweep(let sweep) = feature.operation else {
        Issue.record("Agent must create a sweep feature.")
        return
    }
    #expect(result.commandName == "createSweep")
    #expect(result.didMutate)
    #expect(sweep.sections == [.curve(SweepCurveSectionReference(featureID: sectionID))])
    #expect(session.document.productMetadata.sceneNodes.values.first {
        $0.reference == .body(sweepID)
    }?.object?.sourceSection == .curve(sectionID))
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    #expect(body.kind == .sheet)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentCreatesStandaloneBooleanThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let targetID = try agentCreateBooleanBox(
        in: &document,
        name: "Agent Boolean Target",
        minX: -0.020,
        minY: -0.010,
        maxX: 0.020,
        maxY: 0.010
    )
    let toolID = try agentCreateBooleanBox(
        in: &document,
        name: "Agent Boolean Tool",
        minX: 0.020,
        minY: -0.010,
        maxX: 0.040,
        maxY: 0.010
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBoolean(
                name: "Agent Boolean Union",
                targets: [BooleanTargetReference(featureID: targetID)],
                tool: BooleanToolReference(featureID: toolID),
                operation: .union,
                keepTools: false
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a Boolean command result.")
        return
    }
    let booleanID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[booleanID])
    let evaluated = try CADPipeline.modelingDefault(for: session.document).evaluate(
        session.document.cadDocument
    )

    guard case .boolean(let boolean) = feature.operation else {
        Issue.record("Agent must create a Boolean feature.")
        return
    }

    #expect(result.commandName == "createBoolean")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(boolean.targets == [BooleanTargetReference(featureID: targetID)])
    #expect(boolean.tool == BooleanToolReference(featureID: toolID))
    #expect(boolean.operation == .union)
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(evaluated.brep.bodies.count == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentReturnsBooleanEvaluationPlanWithoutMutatingDocument() async throws {
    var document = DesignDocument.empty()
    let targetID = try agentCreateBooleanBox(
        in: &document,
        name: "Agent Boolean Plan Target",
        minX: -0.020,
        minY: -0.020,
        maxX: 0.020,
        maxY: 0.020
    )
    let toolID = try agentCreateBooleanBox(
        in: &document,
        name: "Agent Boolean Plan Tool",
        minX: -0.010,
        minY: -0.010,
        maxX: 0.010,
        maxY: 0.010
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)
    let initialGeneration = session.generation
    let initialFeatureOrder = session.document.cadDocument.designGraph.order

    let response = server.handle(
        .booleanEvaluationPlan(
            sessionID: sessionID,
            targets: [BooleanTargetReference(featureID: targetID)],
            tool: BooleanToolReference(featureID: toolID),
            operation: .difference,
            keepTools: false,
            expectedGeneration: initialGeneration
        )
    )

    guard case .booleanEvaluationPlan(let plan) = response else {
        Issue.record("Agent must return a Boolean evaluation plan.")
        return
    }

    #expect(plan.status == .supported)
    #expect(plan.operation == .difference)
    #expect(plan.operandKind == .axisAlignedBoxSolids)
    #expect(plan.outputTopologyKind == .zThroughFrame)
    #expect(plan.resultTopologyCounts?.faceCount == 10)
    #expect(plan.resultTopologyCounts?.edgeCount == 24)
    #expect(plan.resultTopologyCounts?.vertexCount == 16)
    #expect(plan.topologyNameSchemes.contains(.frameHoleSideFaces))
    #expect(plan.topologyNameSchemes.contains(.frameBridgeEdges))
    #expect(plan.topologySlots.count == 51)
    #expect(plan.topologySlots.contains(BooleanEvaluationTopologySlot(
        role: .sideFace,
        subshape: "frame:holeFace:maxX"
    )))
    #expect(plan.checks.last?.kind == .capabilityDecision)
    #expect(plan.checks.last?.status == .passed)
    #expect(session.generation == initialGeneration)
    #expect(session.document.cadDocument.designGraph.order == initialFeatureOrder)
}

@MainActor
@Test func agentBooleanEvaluationTopologySlotsMatchCreatedTopologySummary() async throws {
    var document = DesignDocument.empty()
    let targetID = try agentCreateBooleanBox(
        in: &document,
        name: "Agent Boolean Slot Target",
        minX: -0.020,
        minY: -0.020,
        maxX: 0.020,
        maxY: 0.020
    )
    let toolID = try agentCreateBooleanBox(
        in: &document,
        name: "Agent Boolean Slot Tool",
        minX: -0.010,
        minY: -0.010,
        maxX: 0.010,
        maxY: 0.010
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let planResponse = server.handle(
        .booleanEvaluationPlan(
            sessionID: sessionID,
            targets: [BooleanTargetReference(featureID: targetID)],
            tool: BooleanToolReference(featureID: toolID),
            operation: .difference,
            keepTools: false,
            expectedGeneration: session.generation
        )
    )
    guard case .booleanEvaluationPlan(let plan) = planResponse else {
        Issue.record("Agent must return a Boolean evaluation plan.")
        return
    }
    let plannedSlots = [
        BooleanEvaluationTopologySlot(
            role: .vertex,
            subshape: "frame:hole:corner:maxX:maxY:maxZ"
        ),
        BooleanEvaluationTopologySlot(
            role: .edge,
            subshape: "frame:hole:zEdge:x:maxX:y:maxY"
        ),
        BooleanEvaluationTopologySlot(
            role: .sideFace,
            subshape: "frame:holeFace:maxX"
        ),
    ]
    for slot in plannedSlots {
        #expect(plan.topologySlots.contains(slot))
    }

    let commandResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBoolean(
                name: "Agent Boolean Slot Difference",
                targets: [BooleanTargetReference(featureID: targetID)],
                tool: BooleanToolReference(featureID: toolID),
                operation: .difference,
                keepTools: false
            ),
            expectedGeneration: session.generation
        )
    )
    guard case .command(let commandResult) = commandResponse else {
        Issue.record("Agent must create a Boolean feature.")
        return
    }
    let booleanID = try #require(session.document.cadDocument.designGraph.order.last)

    let topologyResponse = server.handle(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: commandResult.generation
        )
    )
    guard case .topologySummary(let topology) = topologyResponse else {
        Issue.record("Agent must return topology summary after Boolean creation.")
        return
    }

    #expect(commandResult.didMutate)
    #expect(topology.counts.faceCount == 10)
    #expect(topology.counts.edgeCount == 24)
    #expect(topology.counts.vertexCount == 16)
    for slot in plannedSlots {
        #expect(topology.entries.contains { entry in
            entry.sourceFeatureID == booleanID.description
                && entry.generatedRole == slot.role.rawValue
                && entry.subshapeRole == slot.subshape
                && entry.selectionComponentID != nil
        })
    }
}

@MainActor
@Test func agentBooleanEvaluationPlanReportsUnsupportedOperandGateWithoutMutatingDocument() async throws {
    var document = DesignDocument.empty()
    let targetID = try agentCreateBooleanBox(
        in: &document,
        name: "Agent Boolean Unsupported Target",
        minX: -0.020,
        minY: -0.020,
        maxX: 0.020,
        maxY: 0.020
    )
    let toolID = try agentCreateBooleanCylinder(
        in: &document,
        name: "Agent Boolean Unsupported Tool",
        radius: 0.006
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)
    let initialGeneration = session.generation
    let initialFeatureOrder = session.document.cadDocument.designGraph.order

    let response = server.handle(
        .booleanEvaluationPlan(
            sessionID: sessionID,
            targets: [BooleanTargetReference(featureID: targetID)],
            tool: BooleanToolReference(featureID: toolID),
            operation: .difference,
            keepTools: false,
            expectedGeneration: initialGeneration
        )
    )

    guard case .booleanEvaluationPlan(let plan) = response else {
        Issue.record("Agent must return an unsupported Boolean evaluation plan.")
        return
    }

    #expect(plan.status == .unsupported)
    #expect(plan.unsupportedCode == .unsupportedOperandTopology)
    #expect(plan.checks.map(\.kind) == [.requestContract, .sourceBodies, .operandTopology])
    #expect(plan.checks.last?.status == .unsupported)
    #expect(plan.topologySlots.isEmpty)
    #expect(session.generation == initialGeneration)
    #expect(session.document.cadDocument.designGraph.order == initialFeatureOrder)
}

@MainActor
@Test func agentCreatesRevolveSourceThroughAutomationAndCore() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Agent Revolve Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(4.0, .millimeter),
            y: .length(14.0, .millimeter)
        )
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createRevolve(
                name: "Agent Revolved Body",
                profile: ProfileReference(featureID: profileID),
                axis: RevolveAxis(origin: .origin, direction: .unitY),
                angle: .angle(180.0, .degree)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a revolve command result.")
        return
    }
    let revolveID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[revolveID])
    guard case .revolve(let revolve) = feature.operation else {
        Issue.record("Agent must create a revolve feature.")
        return
    }

    #expect(result.commandName == "createRevolve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(revolve.profile == ProfileReference(featureID: profileID))
    #expect(revolve.axis == RevolveAxis(origin: .origin, direction: .unitY))
    #expect(revolve.angle == .angle(180.0, .degree))
    #expect(feature.outputs == [FeatureOutput(role: .body)])
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(result.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@discardableResult
private func agentCreateBooleanBox(
    in document: inout DesignDocument,
    name: String,
    minX: Double,
    minY: Double,
    maxX: Double,
    maxY: Double,
    depth: Double = 0.010
) throws -> FeatureID {
    let sketchID = try document.createRectangleSketchFromCorners(
        name: "\(name) Sketch",
        plane: .xy,
        firstCorner: agentSketchPoint(x: minX, y: minY),
        oppositeCorner: agentSketchPoint(x: maxX, y: maxY)
    )
    return try document.extrudeProfile(
        name: name,
        profile: ProfileReference(featureID: sketchID),
        distance: .length(depth, .meter),
        direction: .normal
    )
}

@discardableResult
private func agentCreateBooleanCylinder(
    in document: inout DesignDocument,
    name: String,
    radius: Double,
    depth: Double = 0.010
) throws -> FeatureID {
    let sketchID = try document.createCircleSketch(
        name: "\(name) Sketch",
        plane: .xy,
        center: agentSketchPoint(x: 0.0, y: 0.0),
        radius: .length(radius, .meter)
    )
    return try document.extrudeProfile(
        name: name,
        profile: ProfileReference(featureID: sketchID),
        distance: .length(depth, .meter),
        direction: .normal
    )
}

@MainActor
@Test func agentCreatesConnectedMultiEntitySweepPathAndSweepThroughAutomation() async throws {
    var document = DesignDocument.empty()
    let profileID = try document.createRectangleSketch(
        name: "Agent Connected Sweep Profile",
        plane: .xy,
        width: .length(2.0, .millimeter),
        height: .length(1.0, .millimeter)
    )
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let pathResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSketch(
                name: "Agent Connected Sweep Path",
                sketch: Sketch(
                    plane: .yz,
                    entities: [
                        SketchEntityID(): .line(SketchLine(
                            start: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(0.0, .millimeter)
                            ),
                            end: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(15.0, .millimeter)
                            )
                        )),
                        SketchEntityID(): .line(SketchLine(
                            start: SketchPoint(
                                x: .length(0.0, .millimeter),
                                y: .length(15.0, .millimeter)
                            ),
                            end: SketchPoint(
                                x: .length(8.0, .millimeter),
                                y: .length(25.0, .millimeter)
                            )
                        )),
                    ]
                ),
                geometryRole: .curve
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let pathResult) = pathResponse else {
        Issue.record("Agent must return a createSketch command result.")
        return
    }
    let pathID = try #require(session.document.cadDocument.designGraph.order.last)

    let sweepResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSweep(
                name: "Agent Connected Multi-Path Sweep",
                sections: [.profile(ProfileReference(featureID: profileID))],
                path: SweepPathReference(featureID: pathID),
                guides: [],
                targets: [],
                options: SweepOptions(cornerStyle: .mitre)
            ),
            expectedGeneration: pathResult.generation
        )
    )
    guard case .command(let sweepResult) = sweepResponse else {
        Issue.record("Agent must return a connected sweep command result.")
        return
    }
    let sweepID = try #require(session.document.cadDocument.designGraph.order.last)
    let pathFeature = try #require(session.document.cadDocument.designGraph.nodes[pathID])
    let sweepFeature = try #require(session.document.cadDocument.designGraph.nodes[sweepID])

    guard case .sketch(let pathSketch) = pathFeature.operation,
          case .sweep(let sweep) = sweepFeature.operation else {
        Issue.record("Agent must create a sketch path and a sweep feature.")
        return
    }
    #expect(pathResult.commandName == "createSketch")
    #expect(pathSketch.entities.count == 2)
    #expect(sweepResult.commandName == "createSweep")
    #expect(sweepResult.generation == DocumentGeneration(2))
    #expect(sweep.path == SweepPathReference(featureID: pathID))
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.evaluationStatus == .valid)
    #expect(sweepResult.diagnostics.contains { diagnostic in diagnostic.severity == .error } == false)
}

@MainActor
@Test func agentMovesParallelLineAngleThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentTwoLineConstrainedSketchDocument(
        name: "Agent Parallel Line Pair",
        constraint: { .parallel($0, $1) }
    )
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
    let sourceLine = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let target = try #require(sourceLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(0.0, .meter),
                deltaY: .length(0.010, .meter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let movedSource = try #require(updatedSummary.entries.first { $0.entityID == setup.firstLineID.description })
    let movedFollower = try #require(updatedSummary.entries.first { $0.entityID == setup.secondLineID.description })
    let expectedFollowerEndOffset = 0.005 / sqrt(2.0)
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(agentLineEntriesAreParallel(movedSource, movedFollower))
    #expect(abs((movedFollower.end?.x ?? -1.0) - expectedFollowerEndOffset) < 1.0e-12)
    #expect(abs((movedFollower.end?.y ?? -1.0) - (0.005 + expectedFollowerEndOffset)) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentMovesConstrainedRectanglePointThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Move Constrained Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
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
    let bottomLine = try #require(summary.entries.first { entry in
        agentIsHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())

    let editResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .moveSketchEntityPoint(
                target: target,
                handle: .lineEnd,
                deltaX: .length(2.0, .millimeter),
                deltaY: .length(0.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = editResponse else {
        Issue.record("Agent must return a command result.")
        return
    }
    let updatedSummary = try SketchEntitySummaryService().summarize(document: session.document)
    let movedBottom = try #require(updatedSummary.entries.first { $0.entityID == bottomLine.entityID })
    let bodyNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    #expect(result.commandName == "moveSketchEntityPoint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs((movedBottom.end?.x ?? -1.0) - 0.012) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.012, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.012, y: 0.005))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.012) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsConstrainedRectangleSideDimensionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Agent Dimensioned Box",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(5.0, .millimeter)
            ),
            depth: .length(3.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
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
    let bottomLine = try #require(summary.entries.first { entry in
        agentIsHorizontalLine(entry, y: 0.0)
    })
    let target = try #require(bottomLine.selectionTarget())

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
    let updatedBottom = try #require(updatedSummary.entries.first { $0.entityID == bottomLine.entityID })
    let dimension = try #require(updatedBottom.dimensions.first { $0.kind == "distance" })
    let bodyNode = try #require(agentBodySceneNode(for: bodyFeatureID, in: session.document))
    #expect(result.commandName == "setSketchEntityDimension")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(abs(dimension.resolvedValue - 0.025) < 1.0e-12)
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.025, y: 0.0))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.025, y: 0.005))
    #expect(agentContainsSketchPoint(updatedSummary, x: 0.0, y: 0.005))
    #expect(abs((bodyNode.object?.properties["size.x"]?.lengthValue ?? -1.0) - 0.025) < 1.0e-12)
    #expect(abs((bodyNode.object?.properties["size.z"]?.lengthValue ?? -1.0) - 0.005) < 1.0e-12)
    #expect(session.evaluationStatus == .valid)
}
