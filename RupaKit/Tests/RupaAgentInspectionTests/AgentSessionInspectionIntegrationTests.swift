import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import RupaAgentIntegrationTestFixtures
import RupaAgentTestFixtures
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentSetsParameterExpressionAndListsParameters() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, id: sessionID)

    let commandResponse = server.handle(
        .setParameterExpression(
            sessionID: sessionID,
            name: "height",
            expression: "width * 2",
            kind: .length,
            defaults: ParameterExpressionDefaults(),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = commandResponse else {
        #expect(Bool(false))
        return
    }

    let listResponse = server.handle(
        .parameters(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .parameters(let parameterList) = listResponse else {
        #expect(Bool(false))
        return
    }
    let height = try #require(parameterList.parameters.first { $0.name == "height" })

    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(parameterList.parameters.count == 2)
    #expect(height.expression == "(width * 2)")
    #expect(abs((height.resolvedValue ?? 0.0) - 0.02) < 0.000_000_000_001)
}

@MainActor
@Test func agentListsParameterSourceFeatureUsages() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(12.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    let width = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    _ = try session.execute(
        .createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .reference(width.id),
            height: .constant(.length(6.0, unit: .millimeter))
        ),
        expectedGeneration: DocumentGeneration(1)
    )
    let profileID = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Profile" }?.id
    )
    _ = try session.execute(
        .extrudeProfile(
            name: "Body",
            profile: ProfileReference(featureID: profileID),
            distance: .reference(width.id),
            direction: .normal
        ),
        expectedGeneration: DocumentGeneration(2)
    )
    server.register(session: session, id: sessionID)

    let listResponse = server.handle(
        .parameters(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .parameters(let parameterList) = listResponse else {
        #expect(Bool(false))
        return
    }
    let listedWidth = try #require(parameterList.parameters.first { $0.name == "width" })

    #expect(listedWidth.sourceUsages.contains { usage in
        usage.featureName == "Profile"
            && usage.operation == "sketch"
            && usage.expressionPath.contains(".line.")
    })
    #expect(listedWidth.sourceUsages.contains { usage in
        usage.featureName == "Body"
            && usage.operation == "extrude"
            && usage.expressionPath == "extrude.distance"
    })
}

@MainActor
@Test func agentDeletesParameterThroughAutomationCommand() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .deleteParameter(name: "width"),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }

    #expect(result.commandName == "deleteParameter")
    #expect(result.message == "Parameter width deleted.")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(session.document.cadDocument.parameters.parameters.isEmpty)
}

@MainActor
@Test func agentRenamesParameterThroughAutomationCommand() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "width",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(0)
    )
    let width = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    _ = try session.execute(
        .upsertParameter(
            name: "doubleWidth",
            expression: .multiply(
                .reference(width.id),
                .constant(.scalar(2.0))
            ),
            kind: .length
        ),
        expectedGeneration: DocumentGeneration(1)
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameParameter(currentName: "width", newName: "siteWidth"),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }

    let parameterResponse = server.handle(
        .parameters(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .parameters(let list) = parameterResponse else {
        #expect(Bool(false))
        return
    }
    let siteWidth = try #require(list.parameters.first { $0.name == "siteWidth" })
    let doubleWidth = try #require(list.parameters.first { $0.name == "doubleWidth" })

    #expect(result.commandName == "renameParameter")
    #expect(result.message == "Parameter width renamed to siteWidth.")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(siteWidth.id == width.id.description)
    #expect(doubleWidth.expression == "(siteWidth * 2)")
    #expect(doubleWidth.dependencyNames == ["siteWidth"])
}
@MainActor
@Test func agentEvaluatesOpenSessionWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Eval Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .evaluate(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .evaluation(let snapshot) = response else {
        #expect(Bool(false))
        return
    }
    #expect(snapshot.status == .valid)
    #expect(snapshot.evaluatedGeneration == DocumentGeneration(1))
    #expect(snapshot.bodyCount == 1)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}
@MainActor
@Test func agentMeasuresOpenSessionWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Measure Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .measurement(let measurement) = response else {
        #expect(Bool(false))
        return
    }
    #expect(measurement.counts.sourceFeatures == 2)
    #expect(measurement.counts.solids == 1)
    #expect(abs(measurement.totals.profileAreaSquareMeters - 0.0002) < 0.000_000_000_001)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000006) < 0.000_000_000_001)
    let solid = try #require(measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentMeasuresGeneratedEdgeOffsetDirectEditSolidWithoutDoubleCountingSourceBody() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

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
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let offsetResult) = offsetResponse else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let measureResponse = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .measurement(let measurement) = measureResponse else {
        #expect(Bool(false))
        return
    }
    let solid = try #require(measurement.solids.first)
    let surfaceArea = try #require(solid.surfaceAreaSquareMeters)
    #expect(offsetResult.didMutate)
    #expect(offsetResult.generation == DocumentGeneration(2))
    #expect(measurement.counts.sourceFeatures == 3)
    #expect(measurement.counts.solids == 1)
    #expect(solid.featureID == offsetFeatureID.description)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000008) < 1.0e-12)
    #expect(surfaceArea > 0.0)
    #expect(measurement.diagnostics.contains { $0.message.contains("Offset Edge") } == false)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentExecutesSymmetricGeneratedEdgeOffsetDirectEditSolid() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    server.register(session: session, id: sessionID)

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
    let supportFaceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.generatedRole == "startFace"
    })
    let supportFaceTarget = try #require(supportFaceEntry.selectionTarget())
    let supportDepth = try #require(supportFaceEntry.center?.z)
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge &&
            entry.curveKind == "line" &&
            agentTopologyPoint(entry.start, isOnDepth: supportDepth) &&
            agentTopologyPoint(entry.end, isOnDepth: supportDepth) &&
            entry.selectionTarget() != nil
    })
    let edgeTarget = try #require(edgeEntry.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: edgeTarget,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(
                    isSymmetric: true,
                    gapFill: .linear,
                    supportTarget: supportFaceTarget
                ),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let offsetResult) = offsetResponse else {
        #expect(Bool(false))
        return
    }
    let offsetFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let feature = try #require(session.document.cadDocument.designGraph.nodes[offsetFeatureID])
    guard case .edgeOffset(let edgeOffset) = feature.operation else {
        Issue.record("Agent symmetric Offset Edge must create an EdgeOffset feature.")
        return
    }

    let measuredResponse = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .measurement(let measurement) = measuredResponse else {
        #expect(Bool(false))
        return
    }
    let evaluatedTopology = try TopologySummaryService().summarize(document: session.document)
    let generatedOffsetEdges = evaluatedTopology.entries.filter { entry in
        entry.kind == .edge &&
            entry.sourceFeatureID == offsetFeatureID.description &&
            entry.generatedRole == "edgeOffset" &&
            entry.subshapeRole == "offsetEdge"
    }

    #expect(offsetResult.didMutate)
    #expect(offsetResult.generation == DocumentGeneration(2))
    #expect(edgeOffset.isSymmetric)
    #expect(measurement.counts.sourceFeatures == 3)
    #expect(measurement.counts.solids == 1)
    #expect(measurement.diagnostics.contains { $0.message.contains("Offset Edge") } == false)
    #expect(generatedOffsetEdges.count == 2)
    #expect(evaluatedTopology.counts.faceCount == 8)
    #expect(evaluatedTopology.counts.edgeCount == 18)
    #expect(evaluatedTopology.counts.vertexCount == 12)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func agentMeasuresSelectedOpenSessionBodyWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Selected Measure Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    #expect(session.selectSceneNode(bodyNodeID))
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .measure(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .measurement(let measurement) = response else {
        #expect(Bool(false))
        return
    }
    #expect(measurement.scope == .selection)
    #expect(measurement.counts.sourceFeatures == 2)
    #expect(measurement.counts.solids == 1)
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 0.000006) < 0.000_000_000_001)
    let solid = try #require(measurement.solids.first)
    let height = try #require(solid.linearDimensions.first { $0.kind == .extrusionHeight })
    #expect(abs(height.meters - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesOpenSessionMeshesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Mesh Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(30.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .meshSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .meshSummary(let meshSummary) = response else {
        #expect(Bool(false))
        return
    }
    let bounds = try #require(meshSummary.bounds)
    #expect(meshSummary.bodyCount == 1)
    #expect(meshSummary.vertexCount > 0)
    #expect(meshSummary.triangleCount > 0)
    #expect(meshSummary.indexedElementCount == meshSummary.triangleCount * 3)
    #expect(abs(bounds.sizeX - 0.01) < 0.000_000_000_001)
    #expect(abs(bounds.sizeY - 0.02) < 0.000_000_000_001)
    #expect(abs(bounds.sizeZ - 0.03) < 0.000_000_000_001)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesOpenSessionSketchEntitiesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Guide Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(8.0, .millimeter),
            startAngle: .angle(0.0, .degree),
            endAngle: .angle(90.0, .degree)
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .sketchEntitySummary(let summary) = response else {
        #expect(Bool(false))
        return
    }
    #expect(summary.counts.sketchCount == 1)
    #expect(summary.counts.entityCount == 1)
    let arc = try #require(summary.entries.first { $0.entityKind == "arc" })
    #expect(abs((arc.radius ?? -1.0) - 0.008) < 0.000_000_001)
    #expect(abs((arc.end?.y ?? -1.0) - 0.008) < 0.000_000_001)
    let target = try #require(arc.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selection) = selectionResponse else {
        #expect(Bool(false))
        return
    }
    #expect(selection.selectedTargets == [target])
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesSelectsAndOffsetsRoundRegionThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Selectable Region",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
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
        Issue.record("Agent must return a sketch summary containing regions.")
        return
    }
    #expect(summary.counts.regionCount == 1)
    let region = try #require(summary.regions.first)
    #expect(abs(region.areaSquareMeters - 0.000_06) < 1.0e-12)
    let target = try #require(region.selectionTarget())

    let selectionResponse = server.handle(
        .selectTargets(
            sessionID: sessionID,
            targets: [target],
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .selection(let selection) = selectionResponse else {
        Issue.record("Agent must select a region target.")
        return
    }
    #expect(selection.selectedTargets == [target])

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a round region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    let offsetEntries = after.entries.filter { $0.sourceFeatureID == offsetRegion.sourceFeatureID }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.areaSquareMeters > 0.000_095)
    #expect(offsetRegion.areaSquareMeters < 0.000_096)
    #expect(offsetEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(offsetEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSymmetricNaturalRegionOffset() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Round Region Gap Fill",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    let summary = try SketchEntitySummaryService().summarize(document: session.document)
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())
    server.register(session: session, id: sessionID)

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(isSymmetric: true, gapFill: .natural),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for symmetric Offset Region.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegions = after.regions.filter { $0.sourceFeatureID != region.sourceFeatureID }
    let areas = offsetRegions.map(\.areaSquareMeters).sorted()
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(after.counts.regionCount == 3)
    #expect(abs((areas.first ?? 0.0) - 0.000_032) < 1.0e-12)
    #expect(abs((areas.last ?? 0.0) - 0.000_096) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesNaturalOffsetForConcaveSourceRegion() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentConcaveLineLoopDocument())
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch summary containing a concave region.")
        return
    }
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .natural),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a concave region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.boundaryPointCount == 6)
    #expect(offsetRegion.boundarySegmentCount == 6)
    #expect(abs(offsetRegion.areaSquareMeters - 0.000_108) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesRoundOffsetForConcaveSourceRegion() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession(document: try agentConcaveLineLoopDocument())
    server.register(session: session, id: sessionID)

    let summaryResponse = server.handle(
        .sketchEntitySummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .sketchEntitySummary(let summary) = summaryResponse else {
        Issue.record("Agent must return a sketch summary containing a concave region.")
        return
    }
    let region = try #require(summary.regions.first)
    let target = try #require(region.selectionTarget())

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetCurve command result for a round concave region offset.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let offsetRegion = try #require(after.regions.first { $0.sourceFeatureID != region.sourceFeatureID })
    let offsetEntries = after.entries.filter { $0.sourceFeatureID == offsetRegion.sourceFeatureID }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(after.counts.regionCount == 2)
    #expect(offsetRegion.boundaryPointCount > 11)
    #expect(offsetRegion.boundarySegmentCount == 11)
    #expect(offsetRegion.areaSquareMeters > 0.000_105_5)
    #expect(offsetRegion.areaSquareMeters < 0.000_108)
    #expect(offsetEntries.filter { $0.entityKind == "line" }.count == 6)
    #expect(offsetEntries.filter { $0.entityKind == "arc" }.count == 5)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesCombinedOffsetRegions() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Combined Region A",
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
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Combined Region B",
            plane: .xy,
            firstCorner: SketchPoint(
                x: .length(11.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            oppositeCorner: SketchPoint(
                x: .length(21.0, .millimeter),
                y: .length(6.0, .millimeter)
            )
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let targets = try before.regions.map { region in
        try #require(region.selectionTarget())
    }
    server.register(session: session, id: sessionID)

    let offsetResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetRegions(
                targets: targets,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(gapFill: .natural),
                combinesRegions: true
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let result) = offsetResponse else {
        Issue.record("Agent must return an offsetRegions command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let newSketches = after.sketches.filter { sketch in
        before.sketches.contains { $0.sourceFeatureID == sketch.sourceFeatureID } == false
    }
    let newRegions = after.regions.filter { region in
        before.regions.contains { $0.sourceFeatureID == region.sourceFeatureID } == false
    }
    #expect(result.commandName == "offsetRegions")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(3))
    #expect(newSketches.count == 1)
    #expect(newRegions.count == 1)
    let unionRegion = try #require(newRegions.first)
    #expect(unionRegion.boundaryPointCount == 4)
    #expect(unionRegion.boundarySegmentCount == 4)
    #expect(abs(unionRegion.areaSquareMeters - 0.000_184) < 1.0e-12)
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.3, .millimeter),
                y: .length(0.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.01031, y: 0.00002),
            options: SnapResolutionOptions(
                usesGrid: true,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 4
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .lineEnd)
    #expect(result.selectedCandidate?.source?.selectionTarget != nil)
    #expect(abs(result.resolvedPoint.x - 0.0103) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(result.candidates.contains { $0.kind == .grid })
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Measured Gap",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: 0.002, y: 0.003, z: 0.0), role: .start),
                .worldPoint(Point3D(x: 0.009, y: 0.003, z: 0.0), role: .end),
            ]
        )
    )
    let measurement = try #require(document.productMetadata.measurements[measurementID])
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00201, y: 0.00301),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(result.selectedCandidate?.kind == .measurementPoint)
    #expect(candidate.measurementSource?.sceneNodeID == measurement.sceneNodeID)
    #expect(candidate.measurementSource?.name == "Agent Measured Gap")
    #expect(candidate.measurementSource?.role == .start)
    #expect(abs(result.resolvedPoint.x - 0.002) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.003) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSketchReferenceMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Measured Source Line",
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
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation,
          let lineEntry = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          }) else {
        Issue.record("Agent measurement snap test requires a line sketch.")
        return
    }
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Source Measurement",
            kind: .distance,
            anchors: [
                .sketchReference(featureID: featureID, reference: .lineEnd(lineEntry.key), role: .end),
                .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
            ]
        )
    )
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.01001, y: 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 12
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a sketch-reference measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .sketchReference)
    #expect(candidate.measurementSource?.sketchReference?.featureID == featureID)
    #expect(candidate.measurementSource?.sketchReference?.reference == .lineEnd(lineEntry.key))
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - 0.010) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSketchCurveParameterMeasurementSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Agent Measured Source Curve Parameter",
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
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation,
          let lineEntry = sketch.entities.first(where: { _, entity in
              if case .line = entity {
                  return true
              }
              return false
          }) else {
        Issue.record("Agent measurement snap test requires a line sketch.")
        return
    }
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Agent Source Curve Parameter Measurement",
            kind: .distance,
            anchors: [
                .sketchCurveParameter(featureID: featureID, entityID: lineEntry.key, parameter: 0.5, role: .point),
                .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
            ]
        )
    )
    let session = EditorSession(document: document)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00501, y: 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 12
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a sketch-curve-parameter measurement snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .measurementPoint &&
            candidate.measurementSource?.measurementID == measurementID &&
            candidate.measurementSource?.anchorIndex == 0
    })
    #expect(candidate.measurementSource?.anchorKind == .sketchCurveParameter)
    #expect(candidate.measurementSource?.sketchCurveParameter?.featureID == featureID)
    #expect(candidate.measurementSource?.sketchCurveParameter?.entityID == lineEntry.key)
    #expect(candidate.measurementSource?.sketchCurveParameter?.parameter == 0.5)
    #expect(abs((candidate.measurementSource?.worldPoint.x ?? 0.0) - 0.005) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.commandStack.canUndo == false)
}

@MainActor
@Test func agentResolvesSnapProjectedOntoActiveConstructionPlane() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Projected Snap Line",
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
    _ = try #require(
        session.createConstructionPlane(
            name: "Agent Right CPlane",
            plane: .yz
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.006, y: 0.00005),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                usesConstructionPlaneProjection: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a construction-plane projected snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .lineClosest)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
}

@MainActor
@Test func agentResolvesGeneratedTopologySnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySummaryService().summarize(document: session.document)
    let edge = try #require(topology.entries.first { entry in
        entry.kind == .edge && entry.start != nil && entry.end != nil && entry.selectionTarget() != nil
    })
    let start = try #require(edge.start)
    let end = try #require(edge.end)
    let midpoint = CADCore.Point2D(
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5
    )
    let edgeTarget = try #require(edge.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: midpoint.x + 0.00001, y: midpoint.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a generated topology snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .edgeMidpoint &&
            candidate.topologySource?.persistentName == edge.persistentName
    })
    #expect(candidate.topologySource?.selectionTarget == edgeTarget)
    #expect(abs(candidate.point.x - midpoint.x) <= 1.0e-12)
    #expect(abs(candidate.point.y - midpoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesPolySplineSurfaceCVSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try #require(session.createPolySplineSurface(
        name: "Agent Surface CV Snap PolySpline",
        sourceMesh: agentPolySplineQuadMesh()
    ))
    let topology = try TopologySummaryService().summarize(document: session.document)
    let vertex = try #require(topology.entries.first { entry in
        entry.kind == .vertex
            && PolySplineSurfaceVertexTarget.canParsePersistentName(entry.persistentName)
            && entry.start != nil
            && entry.selectionTarget() != nil
    })
    let point = try #require(vertex.start)
    let vertexTarget = try #require(vertex.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: point.x + 0.00001, y: point.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a PolySpline Surface CV snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceControlVertex
            && candidate.topologySource?.persistentName == vertex.persistentName
    })
    #expect(result.selectedCandidate?.kind == .surfaceControlVertex)
    #expect(candidate.label == "Surface CV")
    #expect(candidate.topologySource?.selectionTarget == vertexTarget)
    #expect(candidate.topologySource?.worldPoint == point)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesVisibleSurfaceFrameSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let createResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createBSplineSurface(
                name: "Agent Snap Surface Frame",
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
        Issue.record("Agent must discover the created direct B-spline surface.")
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

    let summaryResponse = server.handle(
        .surfaceSourceSummary(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .surfaceSourceSummary(let summary) = summaryResponse else {
        Issue.record("Agent must discover authored trim p-curve references.")
        return
    }
    let trimEdge = try #require(summary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let spanSelection = try #require(trimEdge.parameterCurve.spans.first?.selectionReference)
    let query = SurfaceFrameQuery(selectionReference: spanSelection)
    let displayID = try SurfaceFrameDisplayID(query: query)

    let displayResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSurfaceFrameDisplay(query: query, isVisible: true),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let displayResult) = displayResponse else {
        Issue.record("Agent must display the trim p-curve surface frame.")
        return
    }
    #expect(displayResult.didMutate)

    let frameResponse = server.handle(
        .surfaceFrames(
            sessionID: sessionID,
            queries: [query],
            expectedGeneration: DocumentGeneration(3)
        )
    )
    guard case .surfaceFrames(let frames) = frameResponse,
          let frame = frames.frames.first else {
        Issue.record("Agent must resolve the displayed surface frame.")
        return
    }

    let snapResponse = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: frame.position.x + 0.00001, y: frame.position.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 32
            ),
            expectedGeneration: DocumentGeneration(3)
        )
    )

    guard case .snapResolution(let result) = snapResponse else {
        Issue.record("Agent must return a surface frame snap resolution.")
        return
    }
    let candidate = try #require(result.candidates.first { candidate in
        candidate.kind == .surfaceFrame &&
            candidate.surfaceFrameSource?.displayID == displayID
    })
    #expect(result.selectedCandidate?.kind == .surfaceFrame)
    #expect(candidate.surfaceFrameSource?.query == query)
    #expect(candidate.surfaceFrameSource?.faceID.isEmpty == false)
    #expect(candidate.surfaceFrameSource?.facePersistentNames == frame.facePersistentNames)
    #expect(abs((candidate.surfaceFrameSource?.worldPoint.x ?? 0.0) - frame.position.x) <= 1.0e-12)
    #expect(abs((candidate.surfaceFrameSource?.worldPoint.y ?? 0.0) - frame.position.y) <= 1.0e-12)
    #expect(abs((candidate.surfaceFrameSource?.worldPoint.z ?? 0.0) - frame.position.z) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(3))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesRegionCenterSnapCandidatesWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketch(
            name: "Agent Region Snap Rectangle",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(6.0, .millimeter)
        )
    )
    let featureID = try #require(session.document.cadDocument.designGraph.order.last)
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00002, y: -0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a region snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .regionCenter)
    #expect(result.selectedCandidate?.regionSource?.featureID == featureID)
    #expect(result.selectedCandidate?.regionSource?.sceneNodeID != nil)
    #expect(abs(result.resolvedPoint.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveIntersectionSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Horizontal",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        )
    )
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Vertical",
            plane: .xy,
            start: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(6.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00604, y: 0.00403),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return an intersection snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveIntersection)
    #expect(result.selectedCandidate?.source != nil)
    #expect(result.selectedCandidate?.relatedSource != nil)
    #expect(abs(result.resolvedPoint.x - 0.006) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesTangentSnapWithReferencePointWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createCircleSketch(
            name: "Agent Snap Tangent Circle",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(4.0, .millimeter)
        )
    )
    server.register(session: session, id: sessionID)

    let expected = CADCore.Point2D(
        x: cos(Double.pi / 6.0) * 0.004,
        y: sin(Double.pi / 6.0) * 0.004
    )
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: expected.x + 0.00002, y: expected.y + 0.00001),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: CADCore.Point2D(x: 0.0, y: 0.008)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a tangent snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveTangent)
    #expect(abs(result.resolvedPoint.x - expected.x) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - expected.y) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveAxisSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap Axis Line",
            plane: .yz,
            start: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(5.0, .millimeter),
                y: .length(10.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let referencePoint = CADCore.Point2D(x: 0.0, y: 0.004)
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00502, y: 0.00401),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: referencePoint
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return an axis snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveAxis)
    #expect(result.selectedCandidate?.label == "Y")
    #expect(result.selectedCandidate?.axisSource?.kind == .y)
    #expect(result.selectedCandidate?.axisSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesCurveCoordinatePlaneSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Snap YZ Plane Line",
            plane: .xy,
            start: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(4.0, .millimeter)
            ),
            end: SketchPoint(
                x: .length(10.0, .millimeter),
                y: .length(4.0, .millimeter)
            )
        )
    )
    server.register(session: session, id: sessionID)

    let referencePoint = CADCore.Point2D(x: 0.005, y: 0.0)
    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00502, y: 0.00401),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                suppressedCandidateKinds: [.curveAxis],
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8,
                referencePoint: referencePoint
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a coordinate-plane snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .curveCoordinatePlane)
    #expect(result.selectedCandidate?.label == "YZ")
    #expect(result.selectedCandidate?.coordinatePlaneSource?.kind == .yz)
    #expect(result.selectedCandidate?.coordinatePlaneSource?.referencePoint == referencePoint)
    #expect(abs(result.resolvedPoint.x - 0.005) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.004) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentResolvesControlVertexSnapWithoutMutation() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Snap CV Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(2.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(6.0, .millimeter), y: .length(3.0, .millimeter)),
                SketchPoint(x: .length(8.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .resolveSnap(
            sessionID: sessionID,
            point: CADCore.Point2D(x: 0.00202, y: 0.00301),
            options: SnapResolutionOptions(
                usesGrid: false,
                usesObjects: true,
                gridIntervalMeters: 0.001,
                objectSearchRadiusMeters: 0.0002,
                maximumCandidateCount: 8
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .snapResolution(let result) = response else {
        Issue.record("Agent must return a CV snap resolution.")
        return
    }
    #expect(result.selectedCandidate?.kind == .controlVertex)
    #expect(result.selectedCandidate?.label == "CV")
    #expect(result.selectedCandidate?.source?.controlPointIndex == 1)
    #expect(abs(result.resolvedPoint.x - 0.002) <= 1.0e-12)
    #expect(abs(result.resolvedPoint.y - 0.003) <= 1.0e-12)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}
