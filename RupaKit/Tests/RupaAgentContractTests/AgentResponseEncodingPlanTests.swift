import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import RupaKit
import Testing

@Test
func agentProtocolRejectsRequestAtOneByteAboveTheConfiguredCeilingBeforeDecode() throws {
    let unrestricted = AgentMessageCodec(
        limits: AgentProtocolEncodingLimits(
            maximumRequestByteCount: Int.max,
            maximumResponseByteCount: Int.max
        )
    )
    let requestData = try unrestricted.encode(.status, id: "request-boundary")
    let exact = AgentMessageCodec(
        limits: AgentProtocolEncodingLimits(
            maximumRequestByteCount: requestData.count,
            maximumResponseByteCount: Int.max
        )
    )

    do {
        let exactData = try exact.encode(.status, id: "request-boundary")
        #expect(exactData.count == requestData.count)
        #expect(try exact.decodeRequest(from: exactData) == .status)
    } catch {
        Issue.record("Exact request encode failed: \(error)")
    }
    #expect(try exact.decodeRequest(from: requestData) == .status)

    let overLimit = requestData + Data([0x20])
    do {
        _ = try exact.decodeRequest(from: overLimit)
        Issue.record("A request above the protocol ceiling was decoded.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .requestTooLarge(
                actual: overLimit.count,
                maximum: requestData.count
            )
        )
    }
}

@Test
func agentProtocolRejectsResponseAtOneByteAboveTheConfiguredCeiling() throws {
    let unrestricted = AgentMessageCodec(
        limits: AgentProtocolEncodingLimits(
            maximumRequestByteCount: Int.max,
            maximumResponseByteCount: Int.max
        )
    )
    let response = AgentResponse.failure(
        EditorError(
            code: .commandFailed,
            message: String(repeating: "response-boundary", count: 64)
        )
    )
    let responseData = try unrestricted.encode(
        response,
        id: "response-boundary",
        method: "command.apply"
    )
    let exact = AgentMessageCodec(
        limits: AgentProtocolEncodingLimits(
            maximumRequestByteCount: Int.max,
            maximumResponseByteCount: responseData.count,
            maximumIdentifierUTF8ByteCount: 64,
            maximumProjectIDUTF8ByteCount: 64
        )
    )

    do {
        let exactData = try exact.encode(
            response,
            id: "response-boundary",
            method: "command.apply"
        )
        #expect(exactData.count == responseData.count)
        #expect(
            try exact.decodeResponse(
                from: exactData,
                expectedID: "response-boundary",
                expectedMethod: "command.apply"
            ) == response
        )
    } catch {
        Issue.record("Exact response encode failed: \(error)")
    }
    #expect(
        try exact.decodeResponse(
            from: responseData,
            expectedID: "response-boundary",
            expectedMethod: "command.apply"
        ) == response
    )

    let overLimit = responseData + Data([0x20])
    do {
        _ = try exact.decodeResponseEnvelope(from: overLimit)
        Issue.record("A response above the protocol ceiling was decoded.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .responseTooLarge(
                actual: overLimit.count,
                maximum: responseData.count
            )
        )
    }
}

@Test
func agentResponsePlanRetainsChargeBudgetAndConsumesExactlyOnce() throws {
    let limits = AgentProtocolEncodingLimits(
        maximumRequestByteCount: 1_000_000,
        maximumResponseByteCount: 1_000_000,
        maximumIdentifierUTF8ByteCount: 64,
        maximumProjectIDUTF8ByteCount: 64,
        maximumScalarUTF8ByteCount: 20
    )
    let codec = AgentMessageCodec(limits: limits)
    let resultCharge = SemanticResultCharge(
        requestedOutputCount: 1,
        diagnosticRecordCount: 1,
        diagnosticScalarCount: 3,
        diagnosticStringUTF8ByteCount: 32,
        telemetryRecordCount: 1,
        telemetryScalarCount: 12,
        telemetryStringUTF8ByteCount: 0
    )
    let requestedOutput = AgentSemanticOutputReference(
        node: "box",
        output: "body",
        kind: .sourceBody(role: .body)
    )
    let planReservation = try codec.reserveResponse(
        requestID: "semantic-request",
        method: "program.execute",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: resultCharge
    )
    let plan = planReservation.plan

    #expect(plan.resultCharge == resultCharge)
    #expect(plan.resultBudget.maximumRequestedOutputCount == 1)
    #expect(plan.resultBudget.maximumEvaluatedBodyLookupCount == 1)
    #expect(plan.resultBudget.maximumDiagnosticRecordCount == 1)
    #expect(plan.resultBudget.maximumDiagnosticScalarCount == 3)
    #expect(plan.resultBudget.maximumDiagnosticStringUTF8ByteCount == 32)
    #expect(plan.resultBudget.maximumTelemetryRecordCount == 1)
    #expect(plan.resultBudget.maximumTelemetryScalarCount == 12)
    #expect(plan.resultBudget.maximumTelemetryStringUTF8ByteCount == 0)
    #expect(plan.maximumSuccessEncodedByteCount <= limits.maximumResponseByteCount)
    #expect(plan.committedFailureEncodedByteCount <= limits.maximumResponseByteCount)
    #expect(plan.prepublicationFailureEncodedByteCount <= limits.maximumResponseByteCount)

    let response = AgentResponse.programExecution(
        .success(
            .committed(
                AgentSemanticCommitReceipt(
                    authority: testAuthority,
                    outputs: [
                        AgentSemanticOutputBinding(
                            output: requestedOutput,
                            value: .body(
                                featureID: FeatureID(),
                                role: .body,
                                evaluatedBodyID: BodyID()
                            )
                        ),
                    ],
                    diagnostics: [
                        AgentSemanticDiagnostic(
                            severity: .info,
                            code: nil,
                            message: String(repeating: "d", count: 32)
                        ),
                    ],
                    telemetry: testTelemetry
                )
            )
        )
    )
    let committedFailure = AgentResponse.programExecution(
        .committedFailure(
            AgentSemanticCommittedFailure(
                code: .authorityValidationFailed,
                authority: testAuthority
            )
        )
    )
    let committedFailureReservation = try codec.reserveResponse(
        requestID: "semantic-request",
        method: "program.execute",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: resultCharge
    )
    let committedFailureData = try codec.encode(
        committedFailure,
        consuming: committedFailureReservation
    )
    #expect(!committedFailureData.isEmpty)

    let prepublicationFailure = AgentResponse.programExecution(
        .prepublicationFailure(
            AgentSemanticPrepublicationFailure(
                stage: .responsePlanRejected,
                code: "responseTooLarge"
            )
        )
    )
    let prepublicationFailureReservation = try codec.reserveResponse(
        requestID: "semantic-request",
        method: "program.execute",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: resultCharge
    )
    let prepublicationFailureData = try codec.encode(
        prepublicationFailure,
        consuming: prepublicationFailureReservation
    )
    #expect(!prepublicationFailureData.isEmpty)

    let reservation = try codec.reserveResponse(
        requestID: "semantic-request",
        method: "program.execute",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: resultCharge
    )
    let reservationAlias = reservation
    let encoded = try codec.encode(response, consuming: reservationAlias)
    #expect(!encoded.isEmpty)
    #expect(reservation.isConsumed)

    do {
        _ = try codec.encode(response, consuming: reservation)
        Issue.record("A consumed response reservation was reused.")
    } catch let error as AgentResponseEncodingError {
        #expect(error == .responsePlanAlreadyConsumed)
    }
}

@Test
func agentResponsePlanReservesSeparatorsAndLargestSourceBodyRole() throws {
    let limits = AgentProtocolEncodingLimits(
        maximumRequestByteCount: 1_000_000,
        maximumResponseByteCount: 1_000_000,
        maximumIdentifierUTF8ByteCount: 64,
        maximumProjectIDUTF8ByteCount: 64,
        maximumScalarUTF8ByteCount: 20
    )
    let codec = AgentMessageCodec(limits: limits)
    let quoted = String(repeating: "\"", count: 64)
    let escaped = String(repeating: "\\", count: 64)
    let requestedOutputs = [
        AgentSemanticOutputReference(
            node: quoted,
            output: quoted,
            kind: .sourceBody(role: .sheet)
        ),
        AgentSemanticOutputReference(
            node: escaped,
            output: quoted,
            kind: .sourceBody(role: .sheet)
        ),
    ]
    let charge = SemanticResultCharge(
        requestedOutputCount: 2,
        diagnosticRecordCount: 0,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: 0,
        telemetryRecordCount: 1,
        telemetryScalarCount: 12,
        telemetryStringUTF8ByteCount: 0
    )
    let reservation = try codec.reserveResponse(
        requestID: "separator-request",
        method: "program.execute",
        authority: maximumTestAuthority,
        requestedOutputs: requestedOutputs,
        resultCharge: charge
    )
    let response = AgentResponse.programExecution(
        .success(
            .committed(
                AgentSemanticCommitReceipt(
                    authority: maximumTestAuthority,
                    outputs: requestedOutputs.map { output in
                        AgentSemanticOutputBinding(
                            output: output,
                            value: .body(
                                featureID: maximumTestFeatureID,
                                role: .sheet,
                                evaluatedBodyID: maximumTestBodyID
                            )
                        )
                    },
                    diagnostics: [],
                    telemetry: maximumTestTelemetry
                )
            )
        )
    )

    let data = try codec.encode(response, consuming: reservation)
    #expect(data.count == reservation.plan.maximumSuccessEncodedByteCount)
    #expect(data.count <= reservation.plan.reservedEncodedByteCount)
}

@Test
func agentResponsePlanReturnsFailureOnlyReservationWhenSuccessDoesNotFit() throws {
    let probeLimits = AgentProtocolEncodingLimits(
        maximumRequestByteCount: 1_000_000,
        maximumResponseByteCount: 1_000_000,
        maximumIdentifierUTF8ByteCount: 32,
        maximumProjectIDUTF8ByteCount: 32,
        maximumScalarUTF8ByteCount: 20
    )
    let probeCodec = AgentMessageCodec(limits: probeLimits)
    let boundaryID = String(repeating: "\"", count: 32)
    let requestedOutput = AgentSemanticOutputReference(
        node: "box",
        output: "body",
        kind: .sourceBody(role: .sheet)
    )
    let charge = SemanticResultCharge(
        requestedOutputCount: 1,
        diagnosticRecordCount: 0,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: 0,
        telemetryRecordCount: 1,
        telemetryScalarCount: 12,
        telemetryStringUTF8ByteCount: 0
    )
    let probe = try probeCodec.reserveResponse(
        requestID: boundaryID,
        method: "capability.invoke",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: charge
    )
    let smallResponseLimit = probe.plan.prepublicationFailureEncodedByteCount
    let codec = AgentMessageCodec(
        limits: AgentProtocolEncodingLimits(
            maximumRequestByteCount: 1_000_000,
            maximumResponseByteCount: smallResponseLimit,
            maximumIdentifierUTF8ByteCount: 32,
            maximumProjectIDUTF8ByteCount: 32,
            maximumScalarUTF8ByteCount: 20
        )
    )
    let reservation = try codec.reserveResponse(
        requestID: boundaryID,
        method: "capability.invoke",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: charge
    )
    #expect(reservation.plan.isFailureOnly)
    #expect(
        reservation.plan.maximumSuccessEncodedByteCount
            > codec.limits.maximumResponseByteCount
    )

    let failure = AgentResponse.capabilityExecution(
        .prepublicationFailure(
            AgentSemanticPrepublicationFailure(
                stage: .responsePlanRejected,
                code: DomainCapabilityErrorCode(rawValue: boundaryID)
            )
        )
    )
    let data = try codec.encode(failure, consuming: reservation)
    #expect(data.count == reservation.plan.prepublicationFailureEncodedByteCount)

    let secondReservation = try codec.reserveResponse(
        requestID: boundaryID,
        method: "capability.invoke",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: charge
    )
    do {
        _ = try codec.encode(
            AgentResponse.capabilityExecution(
                .success(
                    .committed(
                        AgentSemanticCommitReceipt(
                            authority: testAuthority,
                            outputs: [],
                            diagnostics: [],
                            telemetry: testTelemetry
                        )
                    )
                )
            ),
            consuming: secondReservation
        )
        Issue.record("A failure-only reservation accepted semantic success.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidPlan(
                "A failure-only reservation accepts only responsePlanRejected."
            )
        )
    }

    let overflowingCharge = SemanticResultCharge(
        requestedOutputCount: 1,
        diagnosticRecordCount: 0,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: UInt64.max,
        telemetryRecordCount: 1,
        telemetryScalarCount: 12,
        telemetryStringUTF8ByteCount: 0
    )
    let overflowReservation = try codec.reserveResponse(
        requestID: boundaryID,
        method: "capability.invoke",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: overflowingCharge
    )
    #expect(overflowReservation.plan.isFailureOnly)
    let overflowData = try codec.encode(
        failure,
        consuming: overflowReservation
    )
    #expect(
        overflowData.count
            == overflowReservation.plan.prepublicationFailureEncodedByteCount
    )

    do {
        try AgentProtocolEncodingLimits(
            maximumRequestByteCount: 1_000_000,
            maximumResponseByteCount: smallResponseLimit - 1,
            maximumIdentifierUTF8ByteCount: 32,
            maximumProjectIDUTF8ByteCount: 32,
            maximumScalarUTF8ByteCount: 20
        ).validate()
        Issue.record("A response ceiling below the fixed prepublication shape was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidLimit(
                name: "maximumResponseByteCount",
                value: smallResponseLimit - 1
            )
        )
    }
}

@Test
func agentResponsePlanRejectsOutputAndDiagnosticChargeViolationsBeforeEncoding() throws {
    let codec = AgentMessageCodec()
    let resultCharge = SemanticResultCharge(
        requestedOutputCount: 1,
        diagnosticRecordCount: 1,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: 4,
        telemetryRecordCount: 1,
        telemetryScalarCount: 12,
        telemetryStringUTF8ByteCount: 0
    )
    let requestedOutput = AgentSemanticOutputReference(
        node: "box",
        output: "body",
        kind: .sourceBody(role: .body)
    )
    let plan = try codec.reserveResponse(
        requestID: "shape-request",
        method: "capability.invoke",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: resultCharge
    ).plan
    let missingOutput = AgentResponse.capabilityExecution(
        .success(
            .committed(
                AgentSemanticCommitReceipt(
                    authority: testAuthority,
                    outputs: [],
                    diagnostics: [],
                    telemetry: testTelemetry
                )
            )
        )
    )
    do {
        try plan.validate(response: missingOutput)
        Issue.record("A committed response with missing output was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidPlan(
                "Committed output references must exactly match requested outputs."
            )
        )
    }

    let diagnosticOverflow = AgentResponse.capabilityExecution(
        .success(
            .committed(
                AgentSemanticCommitReceipt(
                    authority: testAuthority,
                    outputs: [
                        AgentSemanticOutputBinding(
                            output: requestedOutput,
                            value: .body(
                                featureID: FeatureID(),
                                role: .body,
                                evaluatedBodyID: BodyID()
                            )
                        ),
                    ],
                    diagnostics: [
                        AgentSemanticDiagnostic(
                            severity: .info,
                            code: nil,
                            message: "12345"
                        ),
                    ],
                    telemetry: testTelemetry
                )
            )
        )
    )
    do {
        try plan.validate(response: diagnosticOverflow)
        Issue.record("A response above the diagnostic string charge was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .chargeExceedsBudget(
                metric: "diagnosticStringUTF8ByteCount",
                actual: 5,
                maximum: 4
            )
        )
    }
}

@Test
func agentProtocolRejectsUnrepresentableConfiguredFieldCeilings() throws {
    do {
        try AgentProtocolEncodingLimits(maximumResponseByteCount: 128).validate()
        Issue.record("A field ceiling above the response ceiling was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidLimit(
                name: "maximumIdentifierUTF8ByteCount",
                value: 1_024
            )
        )
    }
    do {
        try AgentProtocolEncodingLimits(maximumScalarUTF8ByteCount: 21).validate()
        Issue.record("A scalar ceiling above the wire type maximum was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidLimit(
                name: "maximumScalarUTF8ByteCount",
                value: 21
            )
        )
    }
    do {
        try AgentProtocolEncodingLimits(maximumScalarUTF8ByteCount: 19).validate()
        Issue.record("A scalar ceiling below the wire type maximum was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidLimit(
                name: "maximumScalarUTF8ByteCount",
                value: 19
            )
        )
    }
}

@Test
func agentResponseCorrelationRejectsMismatchedIDAndMethodForErrors() throws {
    let codec = AgentMessageCodec()
    let response = AgentResponse.failure(
        EditorError(code: .commandInvalid, message: "semantic request rejected")
    )
    let data = try codec.encode(
        response,
        id: "actual-request",
        method: "command.apply"
    )

    do {
        _ = try codec.decodeResponse(
            from: data,
            expectedID: "different-request",
            expectedMethod: "program.execute"
        )
        Issue.record("An error response with a mismatched ID was accepted.")
    } catch let error as EditorError {
        #expect(error.code == .agentConnectionFailed)
    }

    do {
        _ = try codec.decodeResponse(
            from: data,
            expectedID: "actual-request",
            expectedMethod: "agent.status"
        )
        Issue.record("An error response with a mismatched method was accepted.")
    } catch let error as EditorError {
        #expect(error.code == .agentConnectionFailed)
    }
}

@Test
func agentProtocolRequiresReservationsForSemanticResponses() throws {
    let codec = AgentMessageCodec()
    let semanticFailure = AgentResponse.programExecution(
        .prepublicationFailure(
            AgentSemanticPrepublicationFailure(
                stage: .responsePlanRejected,
                code: "responseTooLarge"
            )
        )
    )

    do {
        _ = try codec.encode(
            semanticFailure,
            id: "unplanned-response",
            method: "program.execute"
        )
        Issue.record("An unplanned semantic response was encoded.")
    } catch let error as AgentResponseEncodingError {
        #expect(error == .responsePlanRequired(method: "program.execute"))
    }

    let envelope = AgentResponseEnvelope(
        id: "unplanned-error",
        response: .failure(EditorError(code: .commandInvalid, message: "rejected")),
        method: "capability.invoke"
    )
    do {
        _ = try codec.encode(envelope)
        Issue.record("An error envelope on a semantic method bypassed planning.")
    } catch let error as AgentResponseEncodingError {
        #expect(error == .responsePlanRequired(method: "capability.invoke"))
    }
}

@Test
func agentProtocolBoundsRequestIDsByTheResponseCorrelationCeiling() throws {
    let limits = AgentProtocolEncodingLimits(
        maximumRequestByteCount: 1_000_000,
        maximumResponseByteCount: 1_000_000,
        maximumIdentifierUTF8ByteCount: 64,
        maximumProjectIDUTF8ByteCount: 64,
        maximumScalarUTF8ByteCount: 20
    )
    let codec = AgentMessageCodec(limits: limits)
    let exactID = String(repeating: "i", count: 64)
    let exactData = try codec.encode(.status, id: exactID)
    #expect(try codec.decodeRequest(from: exactData) == .status)

    let unrestricted = AgentMessageCodec(
        limits: AgentProtocolEncodingLimits(
            maximumRequestByteCount: 1_000_000,
            maximumResponseByteCount: 1_000_000
        )
    )
    let overLimitID = String(repeating: "i", count: 65)
    let overLimitData = try unrestricted.encode(.status, id: overLimitID)
    do {
        _ = try codec.decodeRequest(from: overLimitData)
        Issue.record("A request ID above the response correlation ceiling was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .identifierTooLarge(
                name: "requestID",
                actual: 65,
                maximum: 64
            )
        )
    }
}

@Test
func agentProtocolRejectsGenericErrorsOnSemanticMethodsDuringDecode() throws {
    let codec = AgentMessageCodec()
    let data = Data(
        """
        {
          "jsonrpc": "2.0",
          "id": "semantic-error",
          "method": "program.execute",
          "error": {
            "code": "command.failed",
            "message": "rejected"
          }
        }
        """.utf8
    )
    do {
        _ = try codec.decodeResponse(
            from: data,
            expectedID: "semantic-error",
            expectedMethod: "program.execute"
        )
        Issue.record("A generic error envelope on a semantic method was decoded.")
    } catch let error as AgentResponseEncodingError {
        #expect(error == .responsePlanRequired(method: "program.execute"))
    }
}

@Test
func agentResponsePlanValidatesPlannedAuthorityIdentityAndPreviewCoordinates() throws {
    let codec = AgentMessageCodec()
    let requestedOutput = AgentSemanticOutputReference(
        node: "box",
        output: "body",
        kind: .sourceBody(role: .body)
    )
    let charge = SemanticResultCharge(
        requestedOutputCount: 1,
        diagnosticRecordCount: 0,
        diagnosticScalarCount: 0,
        diagnosticStringUTF8ByteCount: 0,
        telemetryRecordCount: 1,
        telemetryScalarCount: 12,
        telemetryStringUTF8ByteCount: 0
    )
    let plan = try codec.reserveResponse(
        requestID: "authority-request",
        method: "program.execute",
        authority: testAuthority,
        requestedOutputs: [requestedOutput],
        resultCharge: charge
    ).plan
    let wrongProjectAuthority = AgentProjectAuthorityCoordinate(
        projectID: ProjectID(rawValue: "other-project"),
        documentGeneration: testAuthority.documentGeneration,
        transactionRevision: testAuthority.transactionRevision,
        publicationSequence: testAuthority.publicationSequence,
        workspaceRevision: testAuthority.workspaceRevision
    )
    let wrongPreview = AgentResponse.programExecution(
        .success(
            .preview(
                AgentSemanticPreviewReceipt(
                    authority: wrongProjectAuthority,
                    proposedDocumentGeneration: wrongProjectAuthority.documentGeneration,
                    proposedTransactionRevision: wrongProjectAuthority.transactionRevision,
                    diagnostics: [],
                    telemetry: testTelemetry
                )
            )
        )
    )
    do {
        try plan.validate(response: wrongPreview)
        Issue.record("A preview with a different planned authority was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidPlan(
                "Preview authority must exactly match the planned authority."
            )
        )
    }

    let changedPreview = AgentResponse.programExecution(
        .success(
            .preview(
                AgentSemanticPreviewReceipt(
                    authority: testAuthority,
                    proposedDocumentGeneration: DocumentGeneration(5),
                    proposedTransactionRevision: testAuthority.transactionRevision,
                    diagnostics: [],
                    telemetry: testTelemetry
                )
            )
        )
    )
    do {
        try plan.validate(response: changedPreview)
        Issue.record("A preview with changed planned coordinates was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidPlan(
                "Preview proposed coordinates must match the planned authority."
            )
        )
    }

    let wrongCommitted = AgentResponse.programExecution(
        .success(
            .committed(
                AgentSemanticCommitReceipt(
                    authority: wrongProjectAuthority,
                    outputs: [
                        AgentSemanticOutputBinding(
                            output: requestedOutput,
                            value: .body(
                                featureID: FeatureID(),
                                role: .body,
                                evaluatedBodyID: BodyID()
                            )
                        ),
                    ],
                    diagnostics: [],
                    telemetry: testTelemetry
                )
            )
        )
    )
    do {
        try plan.validate(response: wrongCommitted)
        Issue.record("A committed response for another project was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidPlan(
                "Committed authority must preserve the planned projectID."
            )
        )
    }

    let wrongCommittedFailure = AgentResponse.programExecution(
        .committedFailure(
            AgentSemanticCommittedFailure(
                code: .authorityValidationFailed,
                authority: wrongProjectAuthority
            )
        )
    )
    do {
        try plan.validate(response: wrongCommittedFailure)
        Issue.record("A committed failure for another project was accepted.")
    } catch let error as AgentResponseEncodingError {
        #expect(
            error == .invalidPlan(
                "Committed failure authority must preserve the planned projectID."
            )
        )
    }
}

private let testAuthority = AgentProjectAuthorityCoordinate(
    projectID: ProjectID(rawValue: "encoding-test-project"),
    documentGeneration: DocumentGeneration(4),
    transactionRevision: DocumentTransactionRevision(7),
    publicationSequence: 11,
    workspaceRevision: WorkspaceRevision(13)
)

private let maximumTestFeatureID = FeatureID(
    UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
)

private let maximumTestBodyID = BodyID(
    UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
)

private let maximumTestAuthority = AgentProjectAuthorityCoordinate(
    projectID: ProjectID(rawValue: String(repeating: "\"", count: 64)),
    documentGeneration: DocumentGeneration(UInt64.max),
    transactionRevision: DocumentTransactionRevision(UInt64.max),
    publicationSequence: UInt64.max,
    workspaceRevision: WorkspaceRevision(UInt64.max)
)

private let testTelemetry = AgentSemanticTelemetry(
    compilation: AgentSemanticTelemetry.Compilation(
        decodedValueCount: 1,
        decodedNestingDepth: 1,
        nodeCount: 1,
        edgeCount: 0,
        parameterCount: 0,
        requestedOutputCount: 1,
        localOutputReferenceCount: 0,
        expressionCount: 0,
        expressionDepth: 0,
        expressionWork: 0,
        loweredCommandCount: 1,
        expandedSourceWork: 1
    ),
    execution: AgentSemanticTelemetry.Execution(
        stepCount: 1,
        commandCount: 1,
        inputSlotCount: 0,
        outputSlotCount: 1,
        generatedIdentityCount: 1,
        generatedSourceWork: 1
    )
)

private let maximumTestTelemetry = AgentSemanticTelemetry(
    compilation: AgentSemanticTelemetry.Compilation(
        decodedValueCount: Int.max,
        decodedNestingDepth: Int.max,
        nodeCount: Int.max,
        edgeCount: Int.max,
        parameterCount: Int.max,
        requestedOutputCount: Int.max,
        localOutputReferenceCount: Int.max,
        expressionCount: Int.max,
        expressionDepth: Int.max,
        expressionWork: UInt64.max,
        loweredCommandCount: Int.max,
        expandedSourceWork: UInt64.max
    ),
    execution: AgentSemanticTelemetry.Execution(
        stepCount: Int.max,
        commandCount: Int.max,
        inputSlotCount: Int.max,
        outputSlotCount: Int.max,
        generatedIdentityCount: Int.max,
        generatedSourceWork: UInt64.max
    )
)
