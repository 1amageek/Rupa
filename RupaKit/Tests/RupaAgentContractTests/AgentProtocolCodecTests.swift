import Foundation
import RupaAgentIntegrationTestFixtures
import RupaAgentProtocol
import RupaAutomation
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import Testing

@Test(.timeLimit(.minutes(1)))
func legacyRawCommandMethodsAreRejectedBeforeDispatch() throws {
    let codec = AgentMessageCodec()
    let payloads = [
        """
        {"jsonrpc":"2.0","id":"legacy-request","method":"command.apply","params":{}}
        """,
        """
        {"jsonrpc":"2.0","id":"legacy-batch","method":"command.applyBatch","params":{}}
        """,
    ]

    for payload in payloads {
        do {
            _ = try codec.decodeRequest(from: Data(payload.utf8))
            Issue.record("A legacy raw command request reached protocol dispatch.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
    }

    let responsePayloads = [
        """
        {"jsonrpc":"2.0","id":"legacy-result","method":"command.apply","result":{}}
        """,
        """
        {"jsonrpc":"2.0","id":"legacy-error","method":"command.applyBatch","error":{"code":"command.invalid","message":"rejected"}}
        """,
    ]
    for payload in responsePayloads {
        do {
            _ = try codec.decodeResponse(from: Data(payload.utf8))
            Issue.record("A legacy raw command response reached protocol dispatch.")
        } catch let error as EditorError {
            #expect(error.code == .commandInvalid)
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func documentDescriptionAndValidationRoundTripAsDedicatedMethods() throws {
    let codec = AgentMessageCodec()
    let requests: [(AgentRequest, String)] = [
        (
            .describeDocument(
                sessionID: SelfTestFixtures.sessionID,
                expectedGeneration: DocumentGeneration(4)
            ),
            "document.describe"
        ),
        (
            .validateDocument(
                sessionID: SelfTestFixtures.sessionID,
                expectedGeneration: DocumentGeneration(4)
            ),
            "document.validate"
        ),
    ]

    for (request, method) in requests {
        let data = try codec.encode(request, id: method)
        let envelope = try codec.decodeRequestEnvelope(from: data)
        #expect(envelope.method == method)
        #expect(envelope.params == request)
    }
}

@Test(.timeLimit(.minutes(1)))
func documentDescriptionAndValidationDoNotMutateTheSession() throws {
    let controller = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Typed Reads"))
    let sessionID = UUID()
    _ = controller.register(session: session, id: sessionID)
    let initialGeneration = session.generation
    let initialRevision = session.transactionRevision

    let responses = [
        controller.handle(.describeDocument(
            sessionID: sessionID,
            expectedGeneration: initialGeneration
        )),
        controller.handle(.validateDocument(
            sessionID: sessionID,
            expectedGeneration: initialGeneration
        )),
    ]

    guard case .documentDescription(let description) = responses[0],
          case .documentValidation(let validation) = responses[1] else {
        Issue.record("Dedicated document reads returned the wrong response type.")
        return
    }
    #expect(description.effect == .readOnly)
    #expect(validation.effect == .readOnly)
    #expect(!description.didMutate)
    #expect(!validation.didMutate)
    #expect(session.generation == initialGeneration)
    #expect(session.transactionRevision == initialRevision)
}

@Test(.timeLimit(.minutes(1)))
func retainedAutomationLoweringsRoundTripAsMethodSpecificResponses() throws {
    let codec = AgentMessageCodec()
    let result = AutomationResult(message: "typed result")
    let responses: [(AgentResponse, String)] = [
        (.documentDescription(result), "document.describe"),
        (.documentValidation(result), "document.validate"),
        (.parameterExpression(result), "parameter.setExpression"),
        (.objectDimensionExpression(result), "objectDimension.setExpression"),
        (.sketchEntityDimensionExpression(result), "sketchEntityDimension.setExpression"),
        (.selectionDimensionTargetExpression(result), "selectionDimension.setTargetExpression"),
        (.surfaceFrameDisplay(result), "document.setSurfaceFrameDisplay"),
        (.polySplineSurfaceVertex(result), "document.movePolySplineSurfaceVertex"),
    ]

    for (response, method) in responses {
        let data = try codec.encode(response, id: method, method: method)
        #expect(
            try codec.decodeResponse(
                from: data,
                expectedID: method,
                expectedMethod: method
            ) == response
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func semanticDirectRequestRoundTripsWithExplicitVersionsAndOutputs() throws {
    let codec = AgentMessageCodec()
    let request = AgentRequest.invokeCapability(
        AgentSemanticDirectExecutionRequest(
            sessionID: SelfTestFixtures.sessionID,
            authority: SelfTestFixtures.authority,
            dryRun: false,
            request: AgentSemanticDirectRequest(
                schemaVersion: SelfTestFixtures.schemaVersion,
                operationID: "cad.solid.box",
                operationVersion: SelfTestFixtures.operationVersion,
                arguments: [
                    .init(
                        name: "origin",
                        value: .literal(
                            .point(
                                AgentSemanticPoint3D(
                                    x: 0,
                                    y: 0,
                                    z: 0,
                                    unit: .meter
                                )
                            )
                        )
                    ),
                    .init(
                        name: "width",
                        value: .literal(.number(0.02, unit: .meter))
                    ),
                    .init(
                        name: "height",
                        value: .literal(.number(0.012, unit: .meter))
                    ),
                ],
                requestedOutputs: ["body"]
            )
        )
    )

    let encoded = try codec.encode(request, id: "direct-box-1")
    let decoded = try codec.decodeRequest(from: encoded)
    let envelope = try codec.decodeRequestEnvelope(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let params = try #require(json["params"] as? [String: Any])
    let payload = try #require(params["request"] as? [String: Any])

    #expect(decoded == request)
    #expect(envelope.method == "capability.invoke")
    #expect(payload["schemaVersion"] != nil)
    #expect(payload["operationID"] as? String == "cad.solid.box")
    #expect(payload["operationVersion"] != nil)
    #expect(payload["requestedOutputs"] as? [String] == ["body"])
    #expect(params["invocation"] == nil)
    #expect(params["command"] == nil)
}

@Test(.timeLimit(.minutes(1)))
func semanticProgramRequestRoundTripsParametersAndLocalOutputs() throws {
    let output = AgentSemanticOutputReference(
        node: "box",
        output: "body",
        kind: .sourceBody(role: .body)
    )
    let program = AgentSemanticProgramRequest(
        schemaVersion: SelfTestFixtures.schemaVersion,
        parameters: [
            .init(
                name: "depth",
                value: .number(0.006, unit: .meter)
            ),
        ],
        nodes: [
            .init(
                symbol: "box",
                operationID: "cad.solid.box",
                operationVersion: SelfTestFixtures.operationVersion,
                arguments: [
                    .init(
                        name: "depth",
                        value: .parameter("depth")
                    ),
                    .init(
                        name: "bodyOutput",
                        value: .local(output)
                    ),
                ]
            ),
        ],
        requestedOutputs: [output]
    )
    let request = AgentRequest.executeProgram(
        AgentSemanticProgramExecutionRequest(
            sessionID: SelfTestFixtures.sessionID,
            authority: SelfTestFixtures.authority,
            dryRun: true,
            program: program
        )
    )

    let codec = AgentMessageCodec()
    let encoded = try codec.encode(request, id: "program-box-1")
    let decoded = try codec.decodeRequest(from: encoded)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let params = try #require(json["params"] as? [String: Any])

    #expect(decoded == request)
    #expect(json["method"] as? String == "program.execute")
    #expect(params["program"] != nil)
    #expect(params["invocation"] == nil)
    #expect(params["command"] == nil)
    if case .executeProgram(let decodedRequest) = decoded {
        #expect(decodedRequest.dryRun)
        #expect(decodedRequest.program.requestedOutputs == [output])
        #expect(decodedRequest.program.nodes.first?.arguments.last?.value == .local(output))
    } else {
        Issue.record("Expected program.execute to decode as a semantic program request.")
    }
}

@Test(.timeLimit(.minutes(1)))
func semanticExecutionResultsRoundTripForPreviewCommittedAndFailures() throws {
    let codec = AgentMessageCodec()
    let telemetry = AgentSemanticTelemetry(
        compilation: .init(
            decodedValueCount: 1,
            decodedNestingDepth: 1,
            nodeCount: 1,
            edgeCount: 0,
            parameterCount: 0,
            requestedOutputCount: 0,
            localOutputReferenceCount: 0,
            expressionCount: 0,
            expressionDepth: 0,
            expressionWork: 0,
            loweredCommandCount: 1,
            expandedSourceWork: 1
        ),
        execution: .init(
            stepCount: 1,
            commandCount: 1,
            inputSlotCount: 0,
            outputSlotCount: 0,
            generatedIdentityCount: 0,
            generatedSourceWork: 1
        )
    )
    let preview = AgentResponse.capabilityExecution(
        .success(
            .preview(
                AgentSemanticPreviewReceipt(
                    authority: SelfTestFixtures.authority,
                    proposedDocumentGeneration: DocumentGeneration(1),
                    proposedTransactionRevision: DocumentTransactionRevision(1),
                    diagnostics: [],
                    telemetry: telemetry
                )
            )
        )
    )
    let committed = AgentResponse.programExecution(
        .success(
            .committed(
                AgentSemanticCommitReceipt(
                    authority: SelfTestFixtures.authority,
                    outputs: [],
                    diagnostics: [],
                    telemetry: telemetry
                )
            )
        )
    )
    let prepublication = AgentResponse.capabilityExecution(
        .prepublicationFailure(
            AgentSemanticPrepublicationFailure(
                stage: .authorityRejected,
                code: DomainCapabilityErrorCode("authorityRejected")
            )
        )
    )
    let committedFailure = AgentResponse.programExecution(
        .committedFailure(
            AgentSemanticCommittedFailure(
                code: .authorityValidationFailed,
                authority: SelfTestFixtures.authority
            )
        )
    )

    for (response, method, id) in [
        (preview, "capability.invoke", "preview-1"),
        (committed, "program.execute", "commit-1"),
        (prepublication, "capability.invoke", "prepub-1"),
        (committedFailure, "program.execute", "failure-1"),
    ] {
        do {
            _ = try codec.encode(response, id: id, method: method)
            Issue.record("A semantic response was encoded without a response plan.")
        } catch let error as AgentResponseEncodingError {
            #expect(error == .responsePlanRequired(method: method))
        }

        let reservation = try codec.reserveResponse(
            requestID: id,
            method: method,
            authority: SelfTestFixtures.authority,
            requestedOutputs: [],
            resultCharge: SelfTestFixtures.emptyResultCharge
        )
        let encoded = try codec.encode(response, consuming: reservation)
        let decoded = try codec.decodeResponse(
            from: encoded,
            expectedID: id,
            expectedMethod: method
        )
        #expect(decoded == response)
        #expect(reservation.isConsumed)

        do {
            _ = try codec.encode(response, consuming: reservation)
            Issue.record("A consumed response reservation was reused.")
        } catch let error as AgentResponseEncodingError {
            #expect(error == .responsePlanAlreadyConsumed)
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func semanticProtocolRejectsRawGraphAndAutomationPayloadFields() throws {
    let codec = AgentMessageCodec()
    let directEnvelope = """
    {
      "jsonrpc": "2.0",
      "id": "legacy-direct",
      "method": "capability.invoke",
      "params": {
        "sessionID": "00000000-0000-0000-0000-000000000001",
        "authority": {
          "projectID": "project.test",
          "documentGeneration": {"value": 0},
          "transactionRevision": {"value": 0},
          "publicationSequence": 0,
          "workspaceRevision": {"value": 0}
        },
        "dryRun": false,
        "invocation": {},
        "command": {"name": "createExtrudedRectangle"}
      }
    }
    """.data(using: .utf8)!

    var didRejectDirect = false
    do {
        _ = try codec.decodeRequestEnvelope(from: directEnvelope)
    } catch {
        didRejectDirect = true
    }
    #expect(didRejectDirect)

    let graphEnvelope = """
    {
      "jsonrpc": "2.0",
      "id": "legacy-graph",
      "method": "program.execute",
      "params": {
        "sessionID": "00000000-0000-0000-0000-000000000001",
        "authority": {
          "projectID": "project.test",
          "documentGeneration": {"value": 0},
          "transactionRevision": {"value": 0},
          "publicationSequence": 0,
          "workspaceRevision": {"value": 0}
        },
        "dryRun": false,
        "program": {
          "schemaVersion": {"major": 1, "minor": 0, "patch": 0},
          "parameters": [],
          "nodes": [],
          "requestedOutputs": [],
          "featureGraph": []
        }
      }
    }
    """.data(using: .utf8)!

    var didRejectGraph = false
    do {
        _ = try codec.decodeRequestEnvelope(from: graphEnvelope)
    } catch {
        didRejectGraph = true
    }
    #expect(didRejectGraph)
}

@Test(.timeLimit(.minutes(1)))
func semanticProtocolRejectsDirectLocalReferencesAndDuplicateNamedEntries() throws {
    let codec = AgentMessageCodec()
    let directLocal = """
    {
      "jsonrpc": "2.0",
      "id": "direct-local",
      "method": "capability.invoke",
      "params": {
        "sessionID": "00000000-0000-0000-0000-000000000001",
        "authority": {
          "projectID": "project.test",
          "documentGeneration": {"value": 0},
          "transactionRevision": {"value": 0},
          "publicationSequence": 0,
          "workspaceRevision": {"value": 0}
        },
        "dryRun": false,
        "request": {
          "schemaVersion": {"major": 1, "minor": 0, "patch": 0},
          "operationID": "cad.solid.box",
          "operationVersion": {"major": 1, "minor": 0, "patch": 0},
          "arguments": [
            {
              "name": "body",
              "value": {
                "kind": "local",
                "local": {
                  "node": "box",
                  "output": "body",
                  "kind": {"kind": "sourceBody", "role": "body"}
                }
              }
            }
          ],
          "requestedOutputs": []
        }
      }
    }
    """.data(using: .utf8)!

    var didRejectDirectLocal = false
    do {
        _ = try codec.decodeRequestEnvelope(from: directLocal)
    } catch {
        didRejectDirectLocal = true
    }
    #expect(didRejectDirectLocal)

    let duplicateEntries = """
    {
      "jsonrpc": "2.0",
      "id": "duplicate-program",
      "method": "program.execute",
      "params": {
        "sessionID": "00000000-0000-0000-0000-000000000001",
        "authority": {
          "projectID": "project.test",
          "documentGeneration": {"value": 0},
          "transactionRevision": {"value": 0},
          "publicationSequence": 0,
          "workspaceRevision": {"value": 0}
        },
        "dryRun": false,
        "program": {
          "schemaVersion": {"major": 1, "minor": 0, "patch": 0},
          "parameters": [
            {"name": "depth", "value": {"kind": "number", "number": 1, "unit": "meter"}},
            {"name": "depth", "value": {"kind": "number", "number": 2, "unit": "meter"}}
          ],
          "nodes": [],
          "requestedOutputs": []
        }
      }
    }
    """.data(using: .utf8)!

    var didRejectDuplicate = false
    do {
        _ = try codec.decodeRequestEnvelope(from: duplicateEntries)
    } catch {
        didRejectDuplicate = true
    }
    #expect(didRejectDuplicate)
}

@Test(.timeLimit(.minutes(1)))
func semanticProtocolRejectsOutcomeUnknownAndCorrelatesIDAndMethod() throws {
    let codec = AgentMessageCodec()
    let unknownResult = """
    {
      "jsonrpc": "2.0",
      "id": "unknown-1",
      "method": "capability.invoke",
      "result": {"kind": "outcomeUnknown"}
    }
    """.data(using: .utf8)!

    var didRejectUnknown = false
    do {
        _ = try codec.decodeResponseEnvelope(from: unknownResult)
    } catch {
        didRejectUnknown = true
    }
    #expect(didRejectUnknown)

    let response = AgentResponse.capabilityExecution(
        .prepublicationFailure(
            AgentSemanticPrepublicationFailure(
                stage: .dispatchUnavailable,
                code: AgentSemanticPrepublicationFailure.dispatchUnavailableCode
            )
        )
    )
    let reservation = try codec.reserveResponse(
        requestID: "correlated-1",
        method: "capability.invoke",
        authority: SelfTestFixtures.authority,
        requestedOutputs: [],
        resultCharge: SelfTestFixtures.emptyResultCharge
    )
    let encoded = try codec.encode(response, consuming: reservation)
    var didRejectID = false
    do {
        _ = try codec.decodeResponse(
            from: encoded,
            expectedID: "wrong-id",
            expectedMethod: "capability.invoke"
        )
    } catch {
        didRejectID = true
    }
    #expect(didRejectID)

    var didRejectMethod = false
    do {
        _ = try codec.decodeResponse(
            from: encoded,
            expectedID: "correlated-1",
            expectedMethod: "program.execute"
        )
    } catch {
        didRejectMethod = true
    }
    #expect(didRejectMethod)
}

@Test(.timeLimit(.minutes(1)))
func integrationFixtureRejectsSemanticRoutesBeforeSessionMutation() throws {
    let server = AgentCommandController()
    let session = EditorSession(document: .empty(named: "Fixture"))
    let sessionID = UUID()
    _ = server.register(session: session, id: sessionID)
    let authority = AgentProjectAuthorityCoordinate(
        projectID: session.document.projectID,
        documentGeneration: session.generation,
        transactionRevision: session.transactionRevision,
        publicationSequence: 0,
        workspaceRevision: session.workspaceState.revision
    )
    let direct = AgentRequest.invokeCapability(
        AgentSemanticDirectExecutionRequest(
            sessionID: sessionID,
            authority: authority,
            dryRun: false,
            request: AgentSemanticDirectRequest(
                schemaVersion: SelfTestFixtures.schemaVersion,
                operationID: "cad.solid.box",
                operationVersion: SelfTestFixtures.operationVersion
            )
        )
    )
    let program = AgentRequest.executeProgram(
        AgentSemanticProgramExecutionRequest(
            sessionID: sessionID,
            authority: authority,
            dryRun: true,
            program: AgentSemanticProgramRequest(
                schemaVersion: SelfTestFixtures.schemaVersion,
                nodes: []
            )
        )
    )

    for request in [direct, program] {
        let response = server.handle(request)
        switch response {
        case .capabilityExecution(.prepublicationFailure(let failure)),
             .programExecution(.prepublicationFailure(let failure)):
            #expect(failure.stage == .dispatchUnavailable)
            #expect(failure.publicationDisposition == .notPublished)
            #expect(failure.retryDisposition == .retryPermitted)
        default:
            Issue.record("The integration fixture must fail closed for semantic routes until the project executor is connected.")
        }
    }
    #expect(session.generation == DocumentGeneration(0))
    #expect(session.transactionRevision == DocumentTransactionRevision(0))
}

private enum SelfTestFixtures {
    static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let schemaVersion = AgentSemanticSchemaVersion(major: 1, minor: 0, patch: 0)
    static let operationVersion = AgentSemanticOperationVersion(major: 1, minor: 0, patch: 0)
    static let authority = AgentProjectAuthorityCoordinate(
        projectID: ProjectID(rawValue: "project.test"),
        documentGeneration: DocumentGeneration(0),
        transactionRevision: DocumentTransactionRevision(0),
        publicationSequence: 0,
        workspaceRevision: WorkspaceRevision(0)
    )
    static let emptyResultCharge = SemanticResultCharge(
        requestedOutputCount: 0,
        diagnosticRecordCount: 0,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: 0,
        telemetryRecordCount: 0,
        telemetryScalarCount: 0,
        telemetryStringUTF8ByteCount: 0
    )
}
