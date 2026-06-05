import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentCapabilitiesExposeAutomationCommands() async throws {
    let capabilities = AgentServer().capabilities()

    #expect(capabilities.contains("describeDocument"))
    #expect(capabilities.contains("setDisplayUnit"))
    #expect(capabilities.contains("renameDocument"))
    #expect(capabilities.contains("upsertParameter"))
    #expect(capabilities.contains("deleteParameter"))
    #expect(capabilities.contains("setParameterExpression"))
    #expect(capabilities.contains("listParameters"))
    #expect(capabilities.contains("createComponentDefinition"))
    #expect(capabilities.contains("createComponentInstance"))
    #expect(capabilities.contains("setSceneNodeVisibility"))
    #expect(capabilities.contains("setSceneNodeLock"))
    #expect(capabilities.contains("setSceneNodeTransform"))
    #expect(capabilities.contains("setComponentInstanceVisibility"))
    #expect(capabilities.contains("setComponentInstanceLock"))
    #expect(capabilities.contains("setComponentInstanceTransform"))
    #expect(capabilities.contains("createSectionPlane"))
    #expect(capabilities.contains("createLineSketch"))
    #expect(capabilities.contains("createCircleSketch"))
    #expect(capabilities.contains("createRectangleSketch"))
    #expect(capabilities.contains("addSketchConstraint"))
    #expect(capabilities.contains("extrudeProfile"))
    #expect(capabilities.contains("createExtrudedRectangle"))
    #expect(capabilities.contains("createExtrudedRectangleFromCorners"))
    #expect(capabilities.contains("createExtrudedCircle"))
    #expect(capabilities.contains("evaluateDocument"))
    #expect(capabilities.contains("measureDocument"))
    #expect(capabilities.contains("meshSummary"))
    #expect(capabilities.contains("saveDocument"))
    #expect(capabilities.contains("exportDocument"))
    #expect(capabilities.contains("validateDocument"))
}

@Test func agentMessageCodecRoundTripsParameterRequestsAndResponses() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let listRequest = AgentRequest.parameters(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let expressionRequest = AgentRequest.setParameterExpression(
        sessionID: sessionID,
        name: "height",
        expression: "width * 2",
        kind: .length,
        defaults: ParameterExpressionDefaults(lengthUnit: .millimeter),
        expectedGeneration: DocumentGeneration(2)
    )
    let listResponse = AgentResponse.parameters(
        ParameterListResult(
            message: "0 parameters.",
            generation: DocumentGeneration(2),
            dirty: false,
            parameters: [],
            diagnostics: []
        )
    )

    #expect(try codec.decodeRequest(from: try codec.encode(listRequest)) == listRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(expressionRequest)) == expressionRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(listResponse)) == listResponse)
}

@Test func agentMessageCodecRoundTripsCommandRequestAndResponse() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .renameDocument(name: "Encoded"),
        expectedGeneration: DocumentGeneration(3)
    )
    let response = AgentResponse.command(
        AutomationResult(
            message: "Encoded",
            commandName: "renameDocument",
            generation: DocumentGeneration(4),
            didMutate: true
        )
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    #expect(decodedRequest == request)
    #expect(decodedResponse == response)
}

@Test func agentMessageCodecRoundTripsEvaluateAndSaveResponses() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let evaluateRequest = AgentRequest.evaluate(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let evaluateResponse = AgentResponse.evaluation(
        EvaluationSnapshot(
            status: .valid,
            evaluatedGeneration: DocumentGeneration(4),
            bodyCount: 1
        )
    )
    let measureRequest = AgentRequest.measure(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let measureResponse = AgentResponse.measurement(
        MeasurementResult(
            displayUnit: .millimeter,
            counts: MeasurementResult.Counts(sourceFeatures: 2, sketches: 1, profiles: 1, solids: 1),
            totals: MeasurementResult.Totals(
                profileAreaSquareMeters: 0.0001,
                solidVolumeCubicMeters: 0.000001
            )
        )
    )
    let meshRequest = AgentRequest.meshSummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let meshResponse = AgentResponse.meshSummary(
        MeshSummaryResult(
            displayUnit: .millimeter,
            bodyCount: 1,
            vertexCount: 8,
            triangleCount: 12,
            indexedElementCount: 36
        )
    )
    let saveRequest = AgentRequest.save(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(4)
    )
    let saveResponse = AgentResponse.save(
        SaveResult(
            message: "Saved",
            path: "/tmp/model.swcad",
            generation: DocumentGeneration(4),
            dirty: false,
            diagnostics: []
        )
    )

    #expect(try codec.decodeRequest(from: try codec.encode(evaluateRequest)) == evaluateRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(evaluateResponse)) == evaluateResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(measureRequest)) == measureRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(measureResponse)) == measureResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(meshRequest)) == meshRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(meshResponse)) == meshResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(saveRequest)) == saveRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(saveResponse)) == saveResponse)
}

@Test func agentMessageCodecRoundTripsExportRequestAndResponse() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.export(
        sessionID: sessionID,
        outputPath: "/tmp/model.stl",
        expectedGeneration: DocumentGeneration(3),
        options: ExportOptions(
            presetName: "Print STL",
            destinationPolicy: .versioned
        ),
        dryRun: false
    )
    let response = AgentResponse.export(
        ExportResult(
            message: "Exported",
            format: .stl,
            outputPath: "/tmp/model.stl",
            byteCount: 684,
            generation: DocumentGeneration(3),
            presetName: "Print STL",
            outputUnit: .millimeter,
            destinationPolicy: .versioned,
            diagnostics: []
        )
    )

    let decodedRequest = try codec.decodeRequest(from: try codec.encode(request))
    let decodedResponse = try codec.decodeResponse(from: try codec.encode(response))

    #expect(decodedRequest == request)
    #expect(decodedResponse == response)
}

@Test func agentListsRegisteredSessions() async throws {
    let server = AgentServer(socketPath: "/tmp/rupa.sock")
    let sessionID = UUID()
    server.register(
        session: EditorSession(document: .empty(named: "Open Document")),
        path: URL(fileURLWithPath: "/tmp/open.swcad"),
        id: sessionID
    )

    let response = server.handle(.sessions)

    guard case .sessions(let sessions) = response else {
        #expect(Bool(false))
        return
    }
    #expect(sessions.count == 1)
    #expect(sessions[0].id == sessionID)
    #expect(sessions[0].displayName == "Open Document")
    #expect(sessions[0].generation == DocumentGeneration(0))
}

@Test func agentDispatchesCommandThroughAutomationAndCore() async throws {
    let server = AgentServer()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Live")
}

@Test func agentDispatchesModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentServer()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangle(
                name: "Agent Box",
                plane: .xy,
                width: .length(24.0, .millimeter),
                height: .length(12.0, .millimeter),
                depth: .length(6.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedRectangle")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@Test func agentDispatchesCornerFootprintModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentServer()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createExtrudedRectangleFromCorners(
                name: "Agent Footprint Box",
                plane: .xy,
                firstCorner: SketchPoint(
                    x: .length(1.0, .millimeter),
                    y: .length(2.0, .millimeter)
                ),
                oppositeCorner: SketchPoint(
                    x: .length(5.0, .millimeter),
                    y: .length(8.0, .millimeter)
                ),
                depth: .length(3.0, .millimeter),
                direction: .normal
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "createExtrudedRectangleFromCorners")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.designGraph.order.count == 2)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test func agentDispatchesComponentCommandThroughAutomationAndCore() async throws {
    let server = AgentServer()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)

    let definitionResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentDefinition(
                name: "Agent Component",
                rootSceneNodeIDs: []
            ),
            expectedGeneration: DocumentGeneration(0)
        )
    )
    guard case .command(let definitionResult) = definitionResponse else {
        #expect(Bool(false))
        return
    }
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first)

    let instanceResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .createComponentInstance(
                name: "Agent Component A",
                definitionID: definition.id,
                localTransform: .identity
            ),
            expectedGeneration: DocumentGeneration(1)
        )
    )
    guard case .command(let instanceResult) = instanceResponse else {
        #expect(Bool(false))
        return
    }

    let instance = try #require(session.document.productMetadata.componentInstances.values.first)
    let sceneNode = try #require(
        session.document.productMetadata.sceneNodes.values.first {
            $0.reference == .componentInstance(instance.id)
        }
    )
    let sceneNodeTransform = try agentTranslationTransform(x: 0.2, y: 0.0, z: 0.1)
    let transformResponse = server.handle(
        .execute(
            sessionID: sessionID,
            command: .setSceneNodeTransform(
                id: sceneNode.id,
                localTransform: sceneNodeTransform
            ),
            expectedGeneration: DocumentGeneration(2)
        )
    )
    guard case .command(let transformResult) = transformResponse else {
        #expect(Bool(false))
        return
    }

    #expect(definitionResult.commandName == "createComponentDefinition")
    #expect(instanceResult.commandName == "createComponentInstance")
    #expect(instanceResult.generation == DocumentGeneration(2))
    #expect(transformResult.commandName == "setSceneNodeTransform")
    #expect(transformResult.generation == DocumentGeneration(3))
    #expect(instance.definitionID == definition.id)
    #expect(session.document.productMetadata.sceneNodes[sceneNode.id]?.localTransform == sceneNodeTransform)
}

@Test func agentDispatchesCircleModelingCommandThroughAutomationAndCore() async throws {
    let server = AgentServer()
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
    let server = AgentServer()
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

@MainActor
@Test func agentDispatchesSketchConstraintCommandThroughAutomationAndCore() async throws {
    let server = AgentServer()
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
                x: .length(10.0, .millimeter),
                y: .length(0.0, .millimeter)
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
    #expect(result.commandName == "addSketchConstraint")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(2))
    #expect(sketch.constraints == [.horizontal(lineID)])
    #expect(session.evaluationStatus == .valid)
}

@MainActor
@Test func agentSetsParameterExpressionAndListsParameters() async throws {
    let server = AgentServer()
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
@Test func agentDeletesParameterThroughAutomationCommand() async throws {
    let server = AgentServer()
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
@Test func agentEvaluatesOpenSessionWithoutMutation() async throws {
    let server = AgentServer()
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
    let server = AgentServer()
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
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentMeasuresSelectedOpenSessionBodyWithoutMutation() async throws {
    let server = AgentServer()
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
    #expect(session.generation == DocumentGeneration(1))
    #expect(session.commandStack.canUndo)
}

@MainActor
@Test func agentSummarizesOpenSessionMeshesWithoutMutation() async throws {
    let server = AgentServer()
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
@Test func agentSavesOpenFileBackedSessionAndMarksClean() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let url = temporaryDirectory.appendingPathComponent("agent-save.swcad")
    try DocumentFileService().save(.empty(named: "Before"), to: url)
    let server = AgentServer()
    let sessionID = UUID()
    let session = EditorSession(document: try DocumentFileService().load(from: url))
    _ = try session.execute(
        .renameDocument(name: "Saved Live"),
        expectedGeneration: DocumentGeneration(0)
    )
    server.register(session: session, path: url, id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(1)
        )
    )

    guard case .save(let result) = response else {
        #expect(Bool(false))
        return
    }
    let loaded = try DocumentFileService().load(from: url)
    #expect(result.path == url.path)
    #expect(result.generation == DocumentGeneration(1))
    #expect(!result.dirty)
    #expect(!session.isDirty)
    #expect(loaded.cadDocument.metadata.name == "Saved Live")
}

@Test func agentSaveRejectsPathlessSession() async throws {
    let server = AgentServer()
    let sessionID = UUID()
    server.register(session: EditorSession(document: .empty(named: "Pathless")), id: sessionID)

    let response = server.handle(
        .save(
            sessionID: sessionID,
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .commandInvalid)
    #expect(error.message.contains("file path"))
}

@MainActor
@Test func agentExportsOpenSessionWithoutMutation() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let outputURL = temporaryDirectory.appendingPathComponent("agent-box.stl")
    let server = AgentServer()
    let sessionID = UUID()
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Agent Export Box",
            plane: .xy,
            width: .length(20.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(5.0, .millimeter),
            direction: .normal
        )
    )
    server.register(session: session, id: sessionID)

    let response = server.handle(
        .export(
            sessionID: sessionID,
            outputPath: outputURL.path,
            expectedGeneration: DocumentGeneration(1),
            options: ExportOptions(),
            dryRun: false
        )
    )

    guard case .export(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.format == .stl)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.byteCount == 84 + 12 * 50)
    #expect(session.generation == DocumentGeneration(1))
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func agentRejectsGenerationMismatchBeforeMutation() async throws {
    let server = AgentServer()
    let sessionID = UUID()
    let session = EditorSession()
    server.register(session: session, id: sessionID)
    _ = try AutomationRunner().execute(.setDisplayUnit(.meter), in: session)

    let response = server.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Rejected"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .documentGenerationMismatch)
    #expect(session.document.cadDocument.metadata.name == "Untitled")
}

@Test func agentReportsSessionNotFoundForUnknownSession() async throws {
    let server = AgentServer()
    let response = server.handle(
        .execute(
            sessionID: UUID(),
            command: .validateDocument,
            expectedGeneration: nil
        )
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .sessionNotFound)
}

@MainActor
@Test func mainActorAgentBridgeRoutesSessionMutations() async throws {
    let bridge = MainActorAgentBridge()
    let sessionID = UUID()
    let session = EditorSession()
    bridge.register(session: session, id: sessionID)

    let response = bridge.handle(
        .execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Main Actor Live"),
            expectedGeneration: DocumentGeneration(0)
        )
    )

    guard case .command(let result) = response else {
        #expect(Bool(false))
        return
    }
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(session.document.cadDocument.metadata.name == "Main Actor Live")
}

@MainActor
@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoutesCommandThroughMainActorBridge() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let socketPath = AgentSocketPath(socketURL.path)
    let bridge = MainActorAgentBridge()
    let sessionID = UUID()
    let session = EditorSession()
    bridge.register(session: session, id: sessionID)
    let listener = AgentSocketListener(
        mainActorBridge: bridge,
        socketPath: socketPath
    )

    try await listener.start()
    do {
        let request = AgentRequest.execute(
            sessionID: sessionID,
            command: .renameDocument(name: "Socket Main Actor"),
            expectedGeneration: DocumentGeneration(0)
        )
        let response = try await sendThroughDetachedClient(request, socketPath: socketPath)

        guard case .command(let result) = response else {
            #expect(Bool(false))
            await listener.stop()
            return
        }
        #expect(result.didMutate)
        #expect(result.generation == DocumentGeneration(1))
        #expect(session.document.cadDocument.metadata.name == "Socket Main Actor")
        await listener.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoundTripsStatusThroughClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let server = AgentServer()
    server.register(session: EditorSession(document: .empty(named: "Open")))

    try await withRunningListener(server: server, socketURL: socketURL) { listener, client in
        let response = try client.send(.status)

        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(await listener.isRunning)
        #expect(status.running)
        #expect(status.socketPath == socketURL.path)
        #expect(status.sessionCount == 1)
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerRoutesCommandThroughClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let sessionID = UUID()
    let server = AgentServer()
    server.register(session: EditorSession(), id: sessionID)

    try await withRunningListener(server: server, socketURL: socketURL) { _, client in
        let response = try client.send(
            .execute(
                sessionID: sessionID,
                command: .renameDocument(name: "Socket Live"),
                expectedGeneration: DocumentGeneration(0)
            )
        )

        guard case .command(let result) = response else {
            #expect(Bool(false))
            return
        }
        #expect(result.didMutate)
        #expect(result.generation == DocumentGeneration(1))

        let sessionsResponse = try client.send(.sessions)
        guard case .sessions(let sessions) = sessionsResponse else {
            #expect(Bool(false))
            return
        }
        #expect(sessions.first?.displayName == "Socket Live")
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerStopRemovesSocketAndRejectsClient() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    let listener = AgentSocketListener(
        server: AgentServer(),
        socketPath: AgentSocketPath(socketURL.path)
    )
    let client = AgentClient(socketPath: AgentSocketPath(socketURL.path))

    try await listener.start()
    #expect(FileManager.default.fileExists(atPath: socketURL.path))
    await listener.stop()
    #expect(!FileManager.default.fileExists(atPath: socketURL.path))

    var caught: EditorError?
    do {
        _ = try client.send(.status)
    } catch let error as EditorError {
        caught = error
    }
    #expect(caught?.code == .agentConnectionFailed)
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerReplacesStaleSocketFile() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")
    try Data("stale".utf8).write(to: socketURL)

    try await withRunningListener(
        server: AgentServer(),
        socketURL: socketURL
    ) { _, client in
        let response = try client.send(.status)
        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(status.socketPath == socketURL.path)
    }
}

@Test(.timeLimit(.minutes(1))) func agentSocketListenerSurvivesMalformedRequest() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }
    let socketURL = temporaryDirectory.appendingPathComponent("rupa.sock")

    try await withRunningListener(
        server: AgentServer(),
        socketURL: socketURL
    ) { _, client in
        let malformedResponseData = try sendRaw(
            Data("not-json".utf8),
            to: socketURL
        )
        let malformedResponse = try AgentMessageCodec()
            .decodeResponse(from: malformedResponseData)

        guard case .failure(let error) = malformedResponse else {
            #expect(Bool(false))
            return
        }
        #expect(error.code == .commandInvalid)

        let response = try client.send(.status)
        guard case .status(let status) = response else {
            #expect(Bool(false))
            return
        }
        #expect(status.running)
    }
}

private func withRunningListener<T>(
    server: sending AgentServer,
    socketURL: URL,
    operation: (AgentSocketListener, AgentClient) async throws -> T
) async throws -> T {
    let socketPath = AgentSocketPath(socketURL.path)
    let listener = AgentSocketListener(
        server: server,
        socketPath: socketPath
    )
    let client = AgentClient(socketPath: socketPath)

    try await listener.start()
    do {
        let result = try await operation(listener, client)
        await listener.stop()
        return result
    } catch {
        await listener.stop()
        throw error
    }
}

private func sendRaw(_ data: Data, to socketURL: URL) throws -> Data {
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw EditorError(
            code: .agentUnavailable,
            message: "Failed to create test socket. errno=\(errno)"
        )
    }
    defer {
        Darwin.close(descriptor)
    }

    try AgentSocketAddress.withUnixAddress(path: socketURL.path) { address, length in
        guard Darwin.connect(descriptor, address, length) == 0 else {
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Failed to connect test socket. errno=\(errno)"
            )
        }
    }
    try AgentSocketIO.writeAll(data, to: descriptor)
    Darwin.shutdown(descriptor, SHUT_WR)
    return try AgentSocketIO.readAll(from: descriptor)
}

private func sendThroughDetachedClient(
    _ request: AgentRequest,
    socketPath: AgentSocketPath
) async throws -> AgentResponse {
    try await Task.detached {
        let client = AgentClient(socketPath: socketPath)
        return try client.send(request)
    }.value
}

private func makeTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    return temporaryDirectory
}

private func removeTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}

private func agentSketchFeature(
    in document: DesignDocument,
    featureID: FeatureID
) -> Sketch? {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case let .sketch(sketch) = feature.operation else {
        return nil
    }
    return sketch
}

private func agentSingleSketchEntityID(
    in document: DesignDocument,
    featureID: FeatureID
) -> SketchEntityID? {
    guard let sketch = agentSketchFeature(in: document, featureID: featureID),
          sketch.entities.count == 1 else {
        return nil
    }
    return sketch.entities.keys.first
}

private func agentTranslationTransform(
    x: Double,
    y: Double,
    z: Double
) throws -> Transform3D {
    Transform3D(
        matrix: try Matrix4x4(
            values: [
                1.0, 0.0, 0.0, x,
                0.0, 1.0, 0.0, y,
                0.0, 0.0, 1.0, z,
                0.0, 0.0, 0.0, 1.0,
            ]
        )
    )
}
