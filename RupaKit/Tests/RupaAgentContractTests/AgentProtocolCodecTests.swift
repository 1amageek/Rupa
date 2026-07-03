import Testing
import Darwin
import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD
@testable import RupaAgent

@Test func agentHandlesCapabilitySchemaRequest() async throws {
    let server = AgentCommandController()

    let response = server.handle(.capabilities)

    guard case .capabilities(let descriptors) = response else {
        #expect(Bool(false))
        return
    }
    #expect(descriptors == server.capabilityDescriptors())
    #expect(descriptors.contains { $0.name == "moveBodyEdge" && $0.targets == [.edge] })
    #expect(descriptors.contains { $0.name == "moveBodyVertex" && $0.targets == [.vertex] })
    #expect(descriptors.contains { $0.name == "cadInteractionQualityAssessment" && !$0.requiresSession })
    #expect(descriptors.contains { $0.name == "designDisplaySnapshot" && $0.discovery.contains(.designDisplaySnapshot) })
    #expect(descriptors.contains { $0.name == "patternArraySummary" && $0.discovery.contains(.patternArraySummary) })
}

@Test func agentMessageCodecWrapsRequestsInJSONRPCEnvelope() async throws {
    let codec = AgentMessageCodec()

    let encoded = try codec.encode(AgentRequest.status, id: "request-1")
    let envelope = try codec.decodeRequestEnvelope(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let params = try #require(json["params"] as? [String: Any])

    #expect(envelope == AgentRequestEnvelope(id: "request-1", params: .status))
    #expect(json["jsonrpc"] as? String == "2.0")
    #expect(json["id"] as? String == "request-1")
    #expect(json["method"] as? String == "agent.status")
    #expect(params.isEmpty)
    #expect(params["status"] == nil)
}

@Test func agentMessageCodecUsesMethodSpecificRequestParams() async throws {
    let codec = AgentMessageCodec()
    let sessionID = UUID()
    let request = AgentRequest.execute(
        sessionID: sessionID,
        command: .renameDocument(name: "Flat Params"),
        expectedGeneration: DocumentGeneration(7)
    )

    let encoded = try codec.encode(request, id: "request-params")
    let decoded = try codec.decodeRequest(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let params = try #require(json["params"] as? [String: Any])

    #expect(decoded == request)
    #expect(json["method"] as? String == "command.apply")
    #expect(params["execute"] == nil)
    #expect(params["sessionID"] as? String == sessionID.uuidString)
    #expect(params["command"] != nil)
    #expect(params["expectedGeneration"] != nil)
}

@Test func agentMessageCodecWrapsResponsesInJSONRPCEnvelope() async throws {
    let codec = AgentMessageCodec()
    let response = AgentResponse.status(
        AgentStatus(
            running: true,
            socketPath: "/tmp/rupa.sock",
            sessionCount: 2
        )
    )

    let encoded = try codec.encode(response, id: "request-2")
    let decoded = try codec.decodeResponse(from: encoded, expectedID: "request-2")
    let envelope = try codec.decodeResponseEnvelope(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let result = try #require(json["result"] as? [String: Any])

    #expect(decoded == response)
    #expect(envelope.id == "request-2")
    #expect(envelope.method == "agent.status")
    #expect(json["jsonrpc"] as? String == "2.0")
    #expect(json["id"] as? String == "request-2")
    #expect(json["method"] as? String == "agent.status")
    #expect(json["error"] == nil)
    #expect(result["status"] == nil)
    #expect(result["running"] as? Bool == true)
    #expect(result["socketPath"] as? String == "/tmp/rupa.sock")
    #expect(result["sessionCount"] as? Int == 2)
}

@Test func agentMessageCodecWrapsFailuresAsResponseErrors() async throws {
    let codec = AgentMessageCodec()
    let error = EditorError(
        code: .commandInvalid,
        message: "Malformed command."
    )

    let encoded = try codec.encode(
        AgentResponse.failure(error),
        id: "request-3",
        method: "agent.status"
    )
    let decoded = try codec.decodeResponse(
        from: encoded,
        expectedID: "request-3",
        expectedMethod: "agent.status"
    )
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let errorJSON = try #require(json["error"] as? [String: Any])

    #expect(decoded == .failure(error))
    #expect(json["method"] as? String == "agent.status")
    #expect(json["result"] == nil)
    #expect(errorJSON["code"] as? String == EditorError.Code.commandInvalid.rawValue)
    #expect(errorJSON["message"] as? String == "Malformed command.")
}

@Test func agentMessageCodecRejectsRequestMethodPayloadMismatch() async throws {
    let codec = AgentMessageCodec()
    let encoded = Data(
        """
        {
            "jsonrpc": "2.0",
            "id": "request-4",
            "method": "agent.status",
            "params": {
                "sessions": {}
            }
        }
        """.utf8
    )
    var caught: EditorError?

    do {
        _ = try codec.decodeRequestEnvelope(from: encoded)
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func agentMessageCodecRejectsResponseMethodMismatch() async throws {
    let codec = AgentMessageCodec()
    let encoded = try codec.encode(
        AgentResponse.status(
            AgentStatus(
                running: true,
                socketPath: "/tmp/rupa.sock",
                sessionCount: 1
            )
        ),
        id: "request-5"
    )
    var caught: EditorError?

    do {
        _ = try codec.decodeResponse(
            from: encoded,
            expectedID: "request-5",
            expectedMethod: "sessions.list"
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .agentConnectionFailed)
}

@Test func agentMessageCodecTreatsParameterExpressionResponseAsCommandResult() async throws {
    let codec = AgentMessageCodec()
    let response = AgentResponse.command(
        AutomationResult(
            message: "Parameter height updated.",
            commandName: "upsertParameter",
            generation: DocumentGeneration(2),
            didMutate: true
        )
    )

    let encoded = try codec.encode(
        response,
        id: "request-parameter-expression",
        method: "parameter.setExpression"
    )
    let decoded = try codec.decodeResponse(
        from: encoded,
        expectedID: "request-parameter-expression",
        expectedMethod: "parameter.setExpression"
    )
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let result = try #require(json["result"] as? [String: Any])

    #expect(decoded == response)
    #expect(json["method"] as? String == "parameter.setExpression")
    #expect(result["command"] == nil)
    #expect(result["commandName"] as? String == "upsertParameter")
    #expect(result["didMutate"] as? Bool == true)
}

@Test func agentProtocolRawJSONFixturesDecodeRepresentativeRequests() async throws {
    let codec = AgentMessageCodec()
    let sessionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let requestFixtures: [(json: String, validate: (AgentRequestEnvelope) throws -> Void)] = [
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "status-1",
              "method": "agent.status",
              "params": {}
            }
            """,
            { envelope in
                #expect(envelope.id == "status-1")
                #expect(envelope.method == "agent.status")
                #expect(envelope.params == .status)
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "parameters-1",
              "method": "document.parameters",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "expectedGeneration": {
                  "value": 2
                }
              }
            }
            """,
            { envelope in
                guard case .parameters(let decodedSessionID, let expectedGeneration) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(expectedGeneration == DocumentGeneration(2))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "command-1",
              "method": "command.apply",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "command": {
                  "splitSurfaceSpan": {
                    "target": {
                      "kind": "surface",
                      "surface": {
                        "kind": "span",
                        "span": {
                          "surface": {
                            "faceName": {
                              "components": [
                                {
                                  "kind": "feature",
                                  "featureID": "00000000-0000-0000-0000-000000000101"
                                },
                                {
                                  "kind": "generated",
                                  "value": "bSplineSurface"
                                },
                                {
                                  "kind": "subshape",
                                  "value": "patch:0:face"
                                }
                              ]
                            }
                          },
                          "direction": "u",
                          "spanIndex": 0
                        }
                      }
                    },
                    "fraction": {
                      "kind": "constant",
                      "quantity": {
                        "value": 0.5,
                        "kind": "scalar"
                      }
                    }
                  }
                },
                "expectedGeneration": {
                  "value": 3
                }
              }
            }
            """,
            { envelope in
                guard case .execute(let decodedSessionID, let command, let expectedGeneration) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                let expectedFeatureID = try #require(UUID(
                    uuidString: "00000000-0000-0000-0000-000000000101"
                ))
                let expectedTarget = SelectionReference.surface(.span(SurfaceSpanReference(
                    surface: SurfaceReference(
                        faceName: PersistentName(components: [
                            .feature(FeatureID(expectedFeatureID)),
                            .generated("bSplineSurface"),
                            .subshape("patch:0:face"),
                        ])
                    ),
                    direction: .u,
                    spanIndex: 0
                )))
                #expect(decodedSessionID == sessionID)
                #expect(command == .splitSurfaceSpan(target: expectedTarget, fraction: .constant(.scalar(0.5))))
                #expect(expectedGeneration == DocumentGeneration(3))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "parameter-1",
              "method": "parameter.setExpression",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "name": "height",
                "expression": "width * 2",
                "kind": "length",
                "defaults": {
                  "lengthUnit": "millimeter",
                  "angleUnit": "degree"
                },
                "expectedGeneration": {
                  "value": 4
                }
              }
            }
            """,
            { envelope in
                guard case .setParameterExpression(
                    let decodedSessionID,
                    let name,
                    let expression,
                    let kind,
                    let defaults,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(name == "height")
                #expect(expression == "width * 2")
                #expect(kind == .length)
                #expect(defaults == ParameterExpressionDefaults(lengthUnit: .millimeter, angleUnit: .degree))
                #expect(expectedGeneration == DocumentGeneration(4))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "snap-1",
              "method": "snap.resolve",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "point": {
                  "x": 0.012,
                  "y": 0.024
                },
                "options": {
                  "usesGrid": true,
                  "usesObjects": false,
                  "gridIntervalMeters": 0.001,
                  "objectSearchRadiusMeters": 0.002,
                  "maximumCandidateCount": 8
                },
                "expectedGeneration": {
                  "value": 5
                }
              }
            }
            """,
            { envelope in
                guard case .resolveSnap(
                    let decodedSessionID,
                    let point,
                    let options,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(point == Point2D(x: 0.012, y: 0.024))
                #expect(options.usesGrid)
                #expect(!options.usesObjects)
                #expect(options.maximumCandidateCount == 8)
                #expect(expectedGeneration == DocumentGeneration(5))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "surface-analysis-1",
              "method": "document.surfaceAnalysis",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "options": {
                  "sampleDensity": "high"
                },
                "expectedGeneration": {
                  "value": 6
                }
              }
            }
            """,
            { envelope in
                guard case .surfaceAnalysis(
                    let decodedSessionID,
                    let options,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(options == SurfaceAnalysisOptions(sampleDensity: .high))
                #expect(expectedGeneration == DocumentGeneration(6))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "surface-frames-1",
              "method": "document.surfaceFrames",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "queries": [
                  {
                    "faceID": "face-1",
                    "u": 0.25,
                    "v": 0.75
                  }
                ],
                "expectedGeneration": {
                  "value": 7
                }
              }
            }
            """,
            { envelope in
                guard case .surfaceFrames(
                    let decodedSessionID,
                    let queries,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(queries == [SurfaceFrameQuery(faceID: "face-1", u: 0.25, v: 0.75)])
                #expect(expectedGeneration == DocumentGeneration(7))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "selection-1",
              "method": "selection.selectTargets",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "targets": [],
                "expectedGeneration": {
                  "value": 8
                }
              }
            }
            """,
            { envelope in
                guard case .selectTargets(
                    let decodedSessionID,
                    let targets,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(targets.isEmpty)
                #expect(expectedGeneration == DocumentGeneration(8))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "selection-reference-1",
              "method": "selection.selectReferences",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "references": [],
                "expectedGeneration": {
                  "value": 9
                }
              }
            }
            """,
            { envelope in
                guard case .selectReferences(
                    let decodedSessionID,
                    let references,
                    let expectedGeneration
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(references.isEmpty)
                #expect(expectedGeneration == DocumentGeneration(9))
            }
        ),
        (
            """
            {
              "jsonrpc": "2.0",
              "id": "export-1",
              "method": "document.export",
              "params": {
                "sessionID": "00000000-0000-0000-0000-000000000001",
                "outputPath": "/tmp/rupa-fixture.obj",
                "options": {},
                "dryRun": true,
                "expectedGeneration": {
                  "value": 10
                }
              }
            }
            """,
            { envelope in
                guard case .export(
                    let decodedSessionID,
                    let outputPath,
                    let expectedGeneration,
                    let options,
                    let dryRun
                ) = envelope.params else {
                    #expect(Bool(false))
                    return
                }
                #expect(decodedSessionID == sessionID)
                #expect(outputPath == "/tmp/rupa-fixture.obj")
                #expect(expectedGeneration == DocumentGeneration(10))
                #expect(options == ExportOptions())
                #expect(dryRun)
            }
        ),
    ]

    for fixture in requestFixtures {
        let envelope = try codec.decodeRequestEnvelope(from: rawAgentProtocolJSON(fixture.json))
        try fixture.validate(envelope)
    }
}

@Test func agentProtocolRawJSONFixtureDecodesFlatResponses() async throws {
    let codec = AgentMessageCodec()
    let statusResponse = try codec.decodeResponse(
        from: rawAgentProtocolJSON(
            """
            {
              "jsonrpc": "2.0",
              "id": "status-1",
              "method": "agent.status",
              "result": {
                "running": true,
                "socketPath": "/tmp/rupa.sock",
                "sessionCount": 2
              }
            }
            """
        ),
        expectedID: "status-1",
        expectedMethod: "agent.status"
    )
    let parameterResponse = try codec.decodeResponse(
        from: rawAgentProtocolJSON(
            """
            {
              "jsonrpc": "2.0",
              "id": "parameter-1",
              "method": "parameter.setExpression",
              "result": {
                "message": "Parameter height updated.",
                "commandName": "upsertParameter",
                "generation": {
                  "value": 10
                },
                "didMutate": true,
                "diagnostics": []
              }
            }
            """
        ),
        expectedID: "parameter-1",
        expectedMethod: "parameter.setExpression"
    )

    #expect(statusResponse == .status(AgentStatus(running: true, socketPath: "/tmp/rupa.sock", sessionCount: 2)))
    guard case .command(let result) = parameterResponse else {
        #expect(Bool(false))
        return
    }
    #expect(result.commandName == "upsertParameter")
    #expect(result.generation == DocumentGeneration(10))
    #expect(result.didMutate)
}

@Test func agentProtocolRawJSONFixtureDecodesErrorResponse() async throws {
    let codec = AgentMessageCodec()
    let response = try codec.decodeResponse(
        from: rawAgentProtocolJSON(
            """
            {
              "jsonrpc": "2.0",
              "id": "command-1",
              "method": "command.apply",
              "error": {
                "code": "document.generationMismatch",
                "message": "The document has changed since the command was prepared."
              }
            }
            """
        ),
        expectedID: "command-1",
        expectedMethod: "command.apply"
    )

    guard case .failure(let error) = response else {
        #expect(Bool(false))
        return
    }
    #expect(error.code == .documentGenerationMismatch)
    #expect(error.message == "The document has changed since the command was prepared.")
}

@Test func agentProtocolRejectsUnknownTopLevelParamsFromRawJSON() async throws {
    let codec = AgentMessageCodec()
    var caught: EditorError?

    do {
        _ = try codec.decodeRequestEnvelope(
            from: rawAgentProtocolJSON(
                """
                {
                  "jsonrpc": "2.0",
                  "id": "status-unknown-key",
                  "method": "agent.status",
                  "params": {
                    "status": {}
                  }
                }
                """
            )
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("Unsupported params for agent.status") == true)
}

@Test func agentProtocolEncodesStatusResponseAsFlatResult() async throws {
    let codec = AgentMessageCodec()
    let encoded = try codec.encode(
        AgentResponse.status(
            AgentStatus(
                running: true,
                socketPath: "/tmp/rupa.sock",
                sessionCount: 2
            )
        ),
        id: "status-encoded"
    )
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let result = try #require(json["result"] as? [String: Any])

    #expect(json["method"] as? String == "agent.status")
    #expect(result["status"] == nil)
    #expect(result["running"] as? Bool == true)
    #expect(result["sessionCount"] as? Int == 2)
}

private func rawAgentProtocolJSON(_ source: String) -> Data {
    Data(source.utf8)
}

@Test func agentMessageCodecRejectsResponseIDMismatch() async throws {
    let codec = AgentMessageCodec()
    let encoded = try codec.encode(
        AgentResponse.status(
            AgentStatus(
                running: true,
                socketPath: "/tmp/rupa.sock",
                sessionCount: 1
            )
        ),
        id: "actual-request"
    )
    var caught: EditorError?

    do {
        _ = try codec.decodeResponse(from: encoded, expectedID: "expected-request")
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .agentConnectionFailed)
}

@Test func agentMessageCodecRoundTripsParameterRequestsAndResponses() async throws {
    let codec = AgentMessageCodec()
    let capabilitiesRequest = AgentRequest.capabilities
    let qualityAssessmentRequest = AgentRequest.cadInteractionQualityAssessment
    let capabilitiesResponse = AgentResponse.capabilities([
        AgentCapabilityDescriptor(
            name: "topologySummary",
            category: .read,
            summary: "Discover generated topology.",
            access: .agentRequest,
            mutatesDocument: false,
            discovery: [.topologySummary],
            targets: [.face, .edge, .vertex],
            failureMode: "Rejects stale generations before reading."
        ),
    ])
    let sessionID = UUID()
    let listRequest = AgentRequest.parameters(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let constructionPlaneRequest = AgentRequest.constructionPlaneSummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let displaySnapshotRequest = AgentRequest.designDisplaySnapshot(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let patternArraySummaryRequest = AgentRequest.patternArraySummary(
        sessionID: sessionID,
        expectedGeneration: DocumentGeneration(2)
    )
    let objectDimensionTarget = SelectionTarget(sceneNodeID: SceneNodeID())
    let objectDimensionRequest = AgentRequest.objectDimensionSummary(
        sessionID: sessionID,
        targets: [objectDimensionTarget],
        expectedGeneration: DocumentGeneration(2)
    )
    let sketchDimensionTarget = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(SelectionComponentID(rawValue: "sketchEntity:test"))
    )
    let sketchDimensionRequest = AgentRequest.sketchDimensionSummary(
        sessionID: sessionID,
        targets: [sketchDimensionTarget],
        expectedGeneration: DocumentGeneration(2)
    )
    let selectionDimensionID = SelectionDimensionID()
    let selectionDimensionRequest = AgentRequest.selectionDimensionEvaluation(
        sessionID: sessionID,
        dimensionID: selectionDimensionID,
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
    let constructionPlaneResponse = AgentResponse.constructionPlaneSummary(
        ConstructionPlaneSummaryResult(
            activePlaneID: nil,
            planes: []
        )
    )
    let displaySnapshotResponse = AgentResponse.designDisplaySnapshot(
        DesignDisplaySnapshotResult(
            generation: DocumentGeneration(2),
            dirty: false,
            viewportGridSettings: ViewportGridSettings(visualSpacingMode: .fixed),
            viewportGridScale: ViewportGridScaleSnapshot(
                ruler: RulerConfiguration(
                    displayUnit: .meter,
                    minorTickMeters: 0.5,
                    majorTickMeters: 5.0,
                    visibleSpanMeters: 5_000.0
                ),
                settings: ViewportGridSettings(visualSpacingMode: .fixed)
            ),
            workspaceBounds: MeasurementResult.Bounds(
                minX: 0.0,
                minY: 0.0,
                minZ: 0.0,
                maxX: 25_000.0,
                maxY: 10_000.0,
                maxZ: 100.0
            ),
            sketches: [],
            extrudes: [],
            straightPrismSweeps: [],
            bodies: []
        )
    )
    let patternArraySummaryResponse = AgentResponse.patternArraySummary(
        PatternArraySummaryResult(
            generation: DocumentGeneration(2),
            dirty: false,
            patternArrays: []
        )
    )
    let objectDimensionResponse = AgentResponse.objectDimensionSummary(
        ObjectDimensionSummaryResult(
            displayUnit: .millimeter,
            counts: ObjectDimensionSummaryResult.Counts(targetCount: 1, entryCount: 1),
            entries: [
                ObjectDimensionSummaryResult.Entry(
                    target: objectDimensionTarget,
                    sceneNodeID: objectDimensionTarget.sceneNodeID.description,
                    sourceFeatureID: UUID().uuidString,
                    sourceKind: .box,
                    kind: .sizeX,
                    label: "Size X",
                    inputExpression: .length(24.0, .millimeter),
                    resolvedMeters: 0.024,
                    isPrimaryForTarget: true
                ),
            ]
        )
    )
    let sketchDimensionResponse = AgentResponse.sketchDimensionSummary(
        SketchDimensionSummaryResult(
            displayUnit: .millimeter,
            counts: SketchDimensionSummaryResult.Counts(targetCount: 1, entryCount: 1),
            entries: [
                SketchDimensionSummaryResult.Entry(
                    requestedTarget: sketchDimensionTarget,
                    target: sketchDimensionTarget,
                    sceneNodeID: sketchDimensionTarget.sceneNodeID.description,
                    sourceFeatureID: UUID().uuidString,
                    entityID: UUID().uuidString,
                    entityKind: "line",
                    kind: .length,
                    label: "Length",
                    inputExpression: .length(24.0, .millimeter),
                    resolvedValue: 0.024,
                    isPrimaryForTarget: true
                ),
            ]
        )
    )
    let selectionDimensionResponse = AgentResponse.selectionDimensionEvaluation(
        SelectionDimensionEvaluationResult(displayUnit: .millimeter)
    )
    let qualityAssessmentResponse = AgentResponse.cadInteractionQualityAssessment(
        CADInteractionQualityAssessmentService().assess()
    )

    #expect(try codec.decodeRequest(from: try codec.encode(capabilitiesRequest)) == capabilitiesRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(qualityAssessmentRequest)) == qualityAssessmentRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(capabilitiesResponse)) == capabilitiesResponse)
    #expect(try codec.decodeRequest(from: try codec.encode(listRequest)) == listRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(constructionPlaneRequest)) == constructionPlaneRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(displaySnapshotRequest)) == displaySnapshotRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(patternArraySummaryRequest)) == patternArraySummaryRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(objectDimensionRequest)) == objectDimensionRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(sketchDimensionRequest)) == sketchDimensionRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(selectionDimensionRequest)) == selectionDimensionRequest)
    #expect(try codec.decodeRequest(from: try codec.encode(expressionRequest)) == expressionRequest)
    #expect(try codec.decodeResponse(from: try codec.encode(listResponse)) == listResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(constructionPlaneResponse)) == constructionPlaneResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(displaySnapshotResponse)) == displaySnapshotResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(patternArraySummaryResponse)) == patternArraySummaryResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(objectDimensionResponse)) == objectDimensionResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(sketchDimensionResponse)) == sketchDimensionResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(selectionDimensionResponse)) == selectionDimensionResponse)
    #expect(try codec.decodeResponse(from: try codec.encode(qualityAssessmentResponse)) == qualityAssessmentResponse)
}
