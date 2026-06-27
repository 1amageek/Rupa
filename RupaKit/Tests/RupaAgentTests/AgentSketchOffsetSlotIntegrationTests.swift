import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@MainActor
@Test func agentOffsetsSketchCurveThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Offset Source Line",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.entityKind == "line" }
    let offset = try #require(lines.first { entry in
        abs((entry.start?.y ?? -1.0) - 0.002) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.002) < 1.0e-12
    })
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 2)
    #expect(offset.sourceFeatureID != sourceLine.sourceFeatureID)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentOffsetsSketchVertexThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Offset Vertex Rectangle",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetSketchVertex(
                target: target,
                handle: .lineEnd,
                distance: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetSketchVertex command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetSketchVertex")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createRectangleSketchFromCorners(
            name: "Agent Offset Curve Vertex Rectangle",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let bottomLine = try #require(before.entries.first { entry in
        entry.entityKind == "line" &&
            abs((entry.start?.x ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.start?.y ?? -1.0) - 0.0) < 1.0e-12 &&
            abs((entry.end?.x ?? -1.0) - 0.010) < 1.0e-12 &&
            abs((entry.end?.y ?? -1.0) - 0.0) < 1.0e-12
    })
    let target = try #require(bottomLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .lineEnd
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let lines = after.entries.filter { $0.sourceFeatureID == bottomLine.sourceFeatureID && $0.entityKind == "line" }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(lines.count == 6)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveArcEndpointVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentLineArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.arcID.description })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .arcStart
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve arc vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentDispatchesOffsetCurveArcArcEndpointVertexBranchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentArcArcOffsetVertexSketchDocument()
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityID == setup.upperArcID.description })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(1.0, .millimeter),
                options: OffsetCurveOptions(),
                vertexHandle: .arcEnd
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve arc-arc vertex branch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceEntries = after.entries.filter { $0.sourceFeatureID == setup.featureID.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(sourceEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(sourceEntries.filter { $0.entityKind == "arc" }.count == 4)
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchThroughAutomationAndCore() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Slot Source Line",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromOpenLineChainAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentOpenLineChainSlotDocument(name: "Agent Slot Source Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineIDs[0].description })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for an open line-chain.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 4)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Slot Chain",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a line-chain Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromSourceArcAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createArcSketch(
            name: "Agent Slot Source Arc",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceArc = try #require(before.entries.first { $0.entityKind == "arc" })
    let target = try #require(sourceArc.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for a source arc.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Arc Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.isEmpty)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Arc Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for an arc Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromSourceSplineAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createSplineSketch(
            name: "Agent Slot Source Spline",
            plane: .xy,
            spline: SketchSpline(controlPoints: [
                SketchPoint(x: .length(0.0, .millimeter), y: .length(0.0, .millimeter)),
                SketchPoint(x: .length(3.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(7.0, .millimeter), y: .length(4.0, .millimeter)),
                SketchPoint(x: .length(10.0, .millimeter), y: .length(0.0, .millimeter)),
            ])
        )
    )
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceSpline = try #require(before.entries.first { $0.entityKind == "spline" })
    let target = try #require(sourceSpline.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(1.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for a source spline.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Spline Slot" }
    )
    let slotObject = try #require(
        session.document.productMetadata.sceneNodes.values.compactMap(\.object).first { object in
            object.sourceFeatureID == slotFeature.id
        }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotObject.properties["source.kind"] == .text("spline"))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == SlotProfileBuilder.defaultSplineSamplesPerSegment * 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Spline Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a spline Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(3))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentCreatesSlotSketchFromOpenLineArcChainAndExtrudesIt() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let setup = try agentOpenLineArcChainSlotDocument(name: "Agent Slot Source Line Arc Chain")
    let session = EditorSession(document: setup.document)
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityID == setup.lineID.description })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createSlotSketch(
                target: target,
                width: .length(2.0, .millimeter)
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return a createSlotSketch command result for an open line-arc chain.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Slot Source Line Arc Chain Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "createSlotSketch")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 4)

    let extrudeResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .extrudeProfile(
                name: "Agent Extruded Line Arc Slot",
                profile: ProfileReference(featureID: slotFeature.id),
                distance: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let extrudeResult) = extrudeResponse else {
        Issue.record("Agent must return an extrudeProfile command result for a line-arc Slot.")
        return
    }
    #expect(extrudeResult.commandName == "extrudeProfile")
    #expect(extrudeResult.didMutate)
    #expect(extrudeResult.generation == DocumentGeneration(2))
    #expect(session.evaluationStatus == .valid)
    #expect(session.evaluatedBodyCount == 1)
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentActivatesSlotModeThroughOffsetCurve() async throws {
    let server = AgentCommandController()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createLineSketch(
            name: "Agent Offset Slot Source Line",
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
    let before = try SketchEntitySummaryService().summarize(document: session.document)
    let sourceLine = try #require(before.entries.first { $0.entityKind == "line" })
    let target = try #require(sourceLine.selectionTarget())
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .offsetCurve(
                target: target,
                distance: .length(2.0, .millimeter),
                options: OffsetCurveOptions(mode: .slot),
                vertexHandle: nil
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .command(let result) = response else {
        Issue.record("Agent must return an offsetCurve Slot mode command result.")
        return
    }
    let after = try SketchEntitySummaryService().summarize(document: session.document)
    let slotFeature = try #require(
        session.document.cadDocument.designGraph.nodes.values.first { $0.name == "Agent Offset Slot Source Line Slot" }
    )
    let slotEntries = after.entries.filter { $0.sourceFeatureID == slotFeature.id.description }
    #expect(result.commandName == "offsetCurve")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(slotEntries.filter { $0.entityKind == "line" }.count == 2)
    #expect(slotEntries.filter { $0.entityKind == "arc" }.count == 2)
    #expect(session.generation == DocumentGeneration(2))
    #expect(session.commandStack.canUndo)
}
