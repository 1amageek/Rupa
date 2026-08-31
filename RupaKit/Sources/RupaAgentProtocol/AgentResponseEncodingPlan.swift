import Foundation
import RupaCore
import RupaCoreTypes
import RupaDomainFoundation
import RupaKit

/// Immutable response-shape reservation made before a semantic request is
/// allowed to stage in the project authority.
///
/// `SemanticResultCharge` describes decoded semantic shape rather than JSON
/// bytes. This type retains that charge and the caller's project result
/// budget losslessly, then reserves a conservative JSON envelope for both
/// success forms and the fixed committed-failure form. It does not execute,
/// publish, or save a project.
public struct AgentResponseEncodingPlan: Sendable, Equatable {
    public let requestID: String
    public let method: String
    public let authority: AgentProjectAuthorityCoordinate
    public let requestedOutputs: [AgentSemanticOutputReference]
    public let resultCharge: SemanticResultCharge
    public let resultBudget: ProjectSemanticResultBudget
    public let limits: AgentProtocolEncodingLimits

    /// The conservative encoded-byte reservation for either preview or
    /// committed semantic success.
    public let maximumSuccessEncodedByteCount: Int

    /// The encoded-byte reservation for the fixed committed-failure result.
    public let committedFailureEncodedByteCount: Int

    /// The encoded-byte reservation for the largest prepublication failure.
    public let prepublicationFailureEncodedByteCount: Int

    /// The largest response shape permitted by this plan.
    public let reservedEncodedByteCount: Int

    /// Indicates that the success shape cannot fit the configured response
    /// ceiling. Such a reservation is still usable exactly once for the
    /// fixed prepublication failure and must not be staged as a semantic
    /// request.
    public let isFailureOnly: Bool

    init(
        requestID: String,
        method: String,
        authority: AgentProjectAuthorityCoordinate,
        requestedOutputs: [AgentSemanticOutputReference],
        resultCharge: SemanticResultCharge,
        limits: AgentProtocolEncodingLimits = AgentProtocolEncodingLimits()
    ) throws {
        try limits.validate()
        guard method == "capability.invoke" || method == "program.execute" else {
            throw AgentResponseEncodingError.unsupportedPlanMethod(method)
        }
        try Self.validateIdentity(
            requestID,
            name: "requestID",
            maximumByteCount: limits.maximumIdentifierUTF8ByteCount
        )
        let projectID = authority.projectID.rawValue
        guard projectID.utf8.count <= limits.maximumProjectIDUTF8ByteCount else {
            throw AgentResponseEncodingError.invalidPlan(
                "projectID exceeds the configured authority identity ceiling."
            )
        }
        guard projectID.trimmingCharacters(in: .whitespacesAndNewlines) == projectID,
              !projectID.isEmpty,
              projectID.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw AgentResponseEncodingError.invalidPlan(
                "projectID is empty, padded, or contains control characters."
            )
        }
        try Self.validate(authority: authority, limits: limits)
        for output in requestedOutputs {
            try Self.validateIdentity(
                output.node,
                name: "requested output node",
                maximumByteCount: limits.maximumIdentifierUTF8ByteCount
            )
            try Self.validateIdentity(
                output.output,
                name: "requested output name",
                maximumByteCount: limits.maximumIdentifierUTF8ByteCount
            )
            switch output.kind {
            case .feature,
                 .sourceBody,
                 .sceneNode,
                 .componentDefinition,
                 .componentInstance,
                 .patternArraySource:
                break
            default:
                throw AgentResponseEncodingError.invalidPlan(
                    "Requested outputs must be source identity references."
                )
            }
        }

        guard resultCharge.requestedOutputCount == UInt64(requestedOutputs.count) else {
            throw AgentResponseEncodingError.invalidPlan(
                "requested outputs do not match requestedOutputCount."
            )
        }
        for index in requestedOutputs.indices {
            guard !requestedOutputs[..<index].contains(requestedOutputs[index]) else {
                throw AgentResponseEncodingError.invalidPlan(
                    "requested outputs must not contain duplicate references."
                )
            }
        }
        let bodyLookupCount = requestedOutputs.reduce(into: UInt64(0)) { count, output in
            if case .sourceBody = output.kind {
                count += 1
            }
        }
        let resultBudget = ProjectSemanticResultBudget(
            maximumRequestedOutputCount: resultCharge.requestedOutputCount,
            maximumEvaluatedBodyLookupCount: bodyLookupCount,
            maximumDiagnosticRecordCount: resultCharge.diagnosticRecordCount,
            maximumDiagnosticScalarCount: resultCharge.diagnosticScalarCount,
            maximumDiagnosticStringUTF8ByteCount: resultCharge.diagnosticStringUTF8ByteCount,
            maximumTelemetryRecordCount: resultCharge.telemetryRecordCount,
            maximumTelemetryScalarCount: resultCharge.telemetryScalarCount,
            maximumTelemetryStringUTF8ByteCount: resultCharge.telemetryStringUTF8ByteCount
        )

        let diagnosticCount = try Self.intValue(
            resultCharge.diagnosticRecordCount,
            metric: "diagnosticRecordCount"
        )
        let outputCount = requestedOutputs.count
        let diagnosticStringBytes = try Self.intValue(
            try Self.multiplied(
                resultCharge.diagnosticStringUTF8ByteCount,
                by: 6,
                metric: "diagnostic JSON escape bytes"
            ),
            metric: "diagnostic JSON escape bytes"
        )
        let telemetryStringBytes = try Self.intValue(
            try Self.multiplied(
                resultCharge.telemetryStringUTF8ByteCount,
                by: 6,
                metric: "telemetry JSON escape bytes"
            ),
            metric: "telemetry JSON escape bytes"
        )

        let maximumAuthority = Self.maximumAuthority(
            projectIDByteCount: limits.maximumProjectIDUTF8ByteCount,
            scalarByteCount: limits.maximumScalarUTF8ByteCount
        )
        let maximumTelemetry = Self.maximumTelemetry(
            scalarByteCount: limits.maximumScalarUTF8ByteCount
        )
        // This is the longest raw value in the current fixed diagnostic code
        // set; its size is part of every diagnostic-item reservation.
        let maximumDiagnostic = AgentSemanticDiagnostic(
            severity: .warning,
            code: .measurementTessellatedSolidApproximation,
            message: ""
        )
        let maximumOutput = Self.maximumOutput(
            identifierByteCount: limits.maximumIdentifierUTF8ByteCount
        )

        let previewBase = try Self.encodedByteCount(
            response: Self.semanticResponse(
                method: method,
                result: .success(
                    .preview(
                        AgentSemanticPreviewReceipt(
                            authority: maximumAuthority,
                            proposedDocumentGeneration: maximumAuthority.documentGeneration,
                            proposedTransactionRevision: maximumAuthority.transactionRevision,
                            diagnostics: [],
                            telemetry: maximumTelemetry
                        )
                    )
                ),
                id: requestID
            )
        )
        let previewOneDiagnostic = try Self.encodedByteCount(
            response: Self.semanticResponse(
                method: method,
                result: .success(
                    .preview(
                        AgentSemanticPreviewReceipt(
                            authority: maximumAuthority,
                            proposedDocumentGeneration: maximumAuthority.documentGeneration,
                            proposedTransactionRevision: maximumAuthority.transactionRevision,
                            diagnostics: [maximumDiagnostic],
                            telemetry: maximumTelemetry
                        )
                    )
                ),
                id: requestID
            )
        )
        let previewDiagnosticUnit = try Self.subtracting(
            previewOneDiagnostic,
            previewBase,
            metric: "preview diagnostic item"
        )
        let previewDiagnosticItemBytes = try Self.intValue(
            try Self.multiplied(
                UInt64(previewDiagnosticUnit),
                by: UInt64(diagnosticCount),
                metric: "preview diagnostic items"
            ),
            metric: "preview diagnostic items"
        )
        let previewDiagnosticBytes = try Self.adding(
            try Self.adding(
                previewDiagnosticItemBytes,
                max(0, diagnosticCount - 1),
                metric: "preview diagnostic separators"
            ),
            diagnosticStringBytes,
            metric: "preview diagnostic strings"
        )
        let previewBytes = try Self.adding(
            try Self.adding(
                previewBase,
                previewDiagnosticBytes,
                metric: "preview diagnostics"
            ),
            telemetryStringBytes,
            metric: "preview telemetry strings"
        )

        let committedBase = try Self.encodedByteCount(
            response: Self.semanticResponse(
                method: method,
                result: .success(
                    .committed(
                        AgentSemanticCommitReceipt(
                            authority: maximumAuthority,
                            outputs: [],
                            diagnostics: [],
                            telemetry: maximumTelemetry
                        )
                    )
                ),
                id: requestID
            )
        )
        let committedOneOutput = try Self.encodedByteCount(
            response: Self.semanticResponse(
                method: method,
                result: .success(
                    .committed(
                        AgentSemanticCommitReceipt(
                            authority: maximumAuthority,
                            outputs: [maximumOutput],
                            diagnostics: [],
                            telemetry: maximumTelemetry
                        )
                    )
                ),
                id: requestID
            )
        )
        let committedOutputUnit = try Self.subtracting(
            committedOneOutput,
            committedBase,
            metric: "committed output item"
        )
        let committedOneDiagnostic = try Self.encodedByteCount(
            response: Self.semanticResponse(
                method: method,
                result: .success(
                    .committed(
                        AgentSemanticCommitReceipt(
                            authority: maximumAuthority,
                            outputs: [],
                            diagnostics: [maximumDiagnostic],
                            telemetry: maximumTelemetry
                        )
                    )
                ),
                id: requestID
            )
        )
        let committedDiagnosticUnit = try Self.subtracting(
            committedOneDiagnostic,
            committedBase,
            metric: "committed diagnostic item"
        )
        let committedOutputItemBytes = try Self.intValue(
            try Self.multiplied(
                UInt64(committedOutputUnit),
                by: UInt64(outputCount),
                metric: "committed output items"
            ),
            metric: "committed output items"
        )
        let committedOutputBytes = try Self.adding(
            committedOutputItemBytes,
            max(0, outputCount - 1),
            metric: "committed output separators"
        )
        let committedDiagnosticItemBytes = try Self.intValue(
            try Self.multiplied(
                UInt64(committedDiagnosticUnit),
                by: UInt64(diagnosticCount),
                metric: "committed diagnostic items"
            ),
            metric: "committed diagnostic items"
        )
        let committedDiagnosticBytes = try Self.adding(
            committedDiagnosticItemBytes,
            max(0, diagnosticCount - 1),
            metric: "committed diagnostic separators"
        )
        let committedBytes = try Self.adding(
            try Self.adding(
                try Self.adding(
                    committedBase,
                    committedOutputBytes,
                    metric: "committed outputs"
                ),
                committedDiagnosticBytes,
                metric: "committed diagnostics"
            ),
            try Self.adding(
                diagnosticStringBytes,
                telemetryStringBytes,
                metric: "committed strings"
            ),
            metric: "committed telemetry"
        )

        let committedFailureBytes = try Self.encodedByteCount(
            response: Self.semanticResponse(
                method: method,
                result: .committedFailure(
                    AgentSemanticCommittedFailure(
                        code: .authorityValidationFailed,
                        authority: maximumAuthority
                    )
                ),
                id: requestID
            )
        )
        let prepublicationFailureBytes = try Self.encodedByteCount(
            response: Self.semanticResponse(
                method: method,
                result: .prepublicationFailure(
                    AgentSemanticPrepublicationFailure(
                        stage: .responsePlanRejected,
                        code: DomainCapabilityErrorCode(
                            rawValue: String(
                                repeating: "\"",
                                count: limits.maximumIdentifierUTF8ByteCount
                            )
                        )
                    )
                ),
                id: requestID
            )
        )
        let maximumSuccessBytes = max(previewBytes, committedBytes)
        let isFailureOnly = maximumSuccessBytes > limits.maximumResponseByteCount
        let reservedBytes = isFailureOnly
            ? prepublicationFailureBytes
            : max(
                maximumSuccessBytes,
                max(committedFailureBytes, prepublicationFailureBytes)
            )

        guard committedFailureBytes <= limits.maximumResponseByteCount else {
            throw AgentResponseEncodingError.responseTooLarge(
                actual: committedFailureBytes,
                maximum: limits.maximumResponseByteCount
            )
        }
        guard prepublicationFailureBytes <= limits.maximumResponseByteCount else {
            throw AgentResponseEncodingError.responseTooLarge(
                actual: prepublicationFailureBytes,
                maximum: limits.maximumResponseByteCount
            )
        }

        self.requestID = requestID
        self.method = method
        self.authority = authority
        self.requestedOutputs = requestedOutputs
        self.resultCharge = resultCharge
        self.resultBudget = resultBudget
        self.limits = limits
        self.maximumSuccessEncodedByteCount = maximumSuccessBytes
        self.committedFailureEncodedByteCount = committedFailureBytes
        self.prepublicationFailureEncodedByteCount = prepublicationFailureBytes
        self.reservedEncodedByteCount = reservedBytes
        self.isFailureOnly = isFailureOnly
    }

    private init(
        requestID: String,
        method: String,
        authority: AgentProjectAuthorityCoordinate,
        requestedOutputs: [AgentSemanticOutputReference],
        resultCharge: SemanticResultCharge,
        resultBudget: ProjectSemanticResultBudget,
        limits: AgentProtocolEncodingLimits,
        maximumSuccessEncodedByteCount: Int,
        committedFailureEncodedByteCount: Int,
        prepublicationFailureEncodedByteCount: Int,
        reservedEncodedByteCount: Int,
        isFailureOnly: Bool
    ) {
        self.requestID = requestID
        self.method = method
        self.authority = authority
        self.requestedOutputs = requestedOutputs
        self.resultCharge = resultCharge
        self.resultBudget = resultBudget
        self.limits = limits
        self.maximumSuccessEncodedByteCount = maximumSuccessEncodedByteCount
        self.committedFailureEncodedByteCount = committedFailureEncodedByteCount
        self.prepublicationFailureEncodedByteCount = prepublicationFailureEncodedByteCount
        self.reservedEncodedByteCount = reservedEncodedByteCount
        self.isFailureOnly = isFailureOnly
    }

    /// Builds the bounded alternative used when request-specific success
    /// planning cannot complete. Only the prepublication failure is eligible
    /// for this reservation, so no project staging is allowed.
    static func failureOnly(
        requestID: String,
        method: String,
        authority: AgentProjectAuthorityCoordinate,
        requestedOutputs: [AgentSemanticOutputReference],
        resultCharge: SemanticResultCharge,
        limits: AgentProtocolEncodingLimits
    ) throws -> AgentResponseEncodingPlan {
        try limits.validate()
        guard method == "capability.invoke" || method == "program.execute" else {
            throw AgentResponseEncodingError.unsupportedPlanMethod(method)
        }
        try validateIdentity(
            requestID,
            name: "requestID",
            maximumByteCount: limits.maximumIdentifierUTF8ByteCount
        )
        let bodyLookupCount = requestedOutputs.reduce(into: UInt64(0)) { count, output in
            if case .sourceBody = output.kind {
                count += 1
            }
        }
        let resultBudget = ProjectSemanticResultBudget(
            maximumRequestedOutputCount: resultCharge.requestedOutputCount,
            maximumEvaluatedBodyLookupCount: bodyLookupCount,
            maximumDiagnosticRecordCount: resultCharge.diagnosticRecordCount,
            maximumDiagnosticScalarCount: resultCharge.diagnosticScalarCount,
            maximumDiagnosticStringUTF8ByteCount: resultCharge.diagnosticStringUTF8ByteCount,
            maximumTelemetryRecordCount: resultCharge.telemetryRecordCount,
            maximumTelemetryScalarCount: resultCharge.telemetryScalarCount,
            maximumTelemetryStringUTF8ByteCount: resultCharge.telemetryStringUTF8ByteCount
        )
        let prepublicationFailureBytes = try encodedByteCount(
            response: semanticResponse(
                method: method,
                result: .prepublicationFailure(
                    AgentSemanticPrepublicationFailure(
                        stage: .responsePlanRejected,
                        code: DomainCapabilityErrorCode(
                            rawValue: String(
                                repeating: "\"",
                                count: limits.maximumIdentifierUTF8ByteCount
                            )
                        )
                    )
                ),
                id: requestID
            )
        )
        guard prepublicationFailureBytes <= limits.maximumResponseByteCount else {
            throw AgentResponseEncodingError.responseTooLarge(
                actual: prepublicationFailureBytes,
                maximum: limits.maximumResponseByteCount
            )
        }
        let maximumSuccess = limits.maximumResponseByteCount == Int.max
            ? Int.max
            : limits.maximumResponseByteCount + 1
        return AgentResponseEncodingPlan(
            requestID: requestID,
            method: method,
            authority: authority,
            requestedOutputs: requestedOutputs,
            resultCharge: resultCharge,
            resultBudget: resultBudget,
            limits: limits,
            maximumSuccessEncodedByteCount: maximumSuccess,
            committedFailureEncodedByteCount: 0,
            prepublicationFailureEncodedByteCount: prepublicationFailureBytes,
            reservedEncodedByteCount: prepublicationFailureBytes,
            isFailureOnly: true
        )
    }

    /// Validates the response discriminator before the one permitted encode
    /// attempt. The actual byte count is checked by `AgentMessageCodec`.
    public func validate(response: AgentResponse) throws {
        let result: AgentSemanticExecutionResult
        switch (method, response) {
        case ("capability.invoke", .capabilityExecution(let value)),
             ("program.execute", .programExecution(let value)):
            result = value
        default:
            throw AgentResponseEncodingError.responseDoesNotMatchPlan(
                expectedID: requestID,
                actualID: nil,
                expectedMethod: method,
                actualMethod: response.methodName
            )
        }
        if isFailureOnly {
            guard case .prepublicationFailure(let failure) = result,
                  failure.stage == .responsePlanRejected else {
                throw AgentResponseEncodingError.invalidPlan(
                    "A failure-only reservation accepts only responsePlanRejected."
                )
            }
        }
        switch result {
        case .success(let success):
            switch success {
            case .preview(let receipt):
                guard receipt.authority == authority else {
                    throw AgentResponseEncodingError.invalidPlan(
                        "Preview authority must exactly match the planned authority."
                    )
                }
                guard receipt.proposedDocumentGeneration == authority.documentGeneration,
                      receipt.proposedTransactionRevision == authority.transactionRevision else {
                    throw AgentResponseEncodingError.invalidPlan(
                        "Preview proposed coordinates must match the planned authority."
                    )
                }
                try Self.validate(authority: receipt.authority, limits: limits)
                try Self.validate(
                    receipt.proposedDocumentGeneration.value,
                    metric: "proposedDocumentGeneration",
                    limits: limits
                )
                try Self.validate(
                    receipt.proposedTransactionRevision.value,
                    metric: "proposedTransactionRevision",
                    limits: limits
                )
                try Self.validate(
                    diagnostics: receipt.diagnostics,
                    charge: resultCharge
                )
                try Self.validate(telemetry: receipt.telemetry, limits: limits)
            case .committed(let receipt):
                guard receipt.outputs.map(\.output) == requestedOutputs else {
                    throw AgentResponseEncodingError.invalidPlan(
                        "Committed output references must exactly match requested outputs."
                    )
                }
                guard receipt.authority.projectID == authority.projectID else {
                    throw AgentResponseEncodingError.invalidPlan(
                        "Committed authority must preserve the planned projectID."
                    )
                }
                for binding in receipt.outputs {
                    try Self.validate(binding: binding)
                }
                try Self.validate(authority: receipt.authority, limits: limits)
                try Self.validate(
                    diagnostics: receipt.diagnostics,
                    charge: resultCharge
                )
                try Self.validate(telemetry: receipt.telemetry, limits: limits)
            }
        case .prepublicationFailure(let failure):
            try Self.validateIdentity(
                failure.code.rawValue,
                name: "prepublication failure code",
                maximumByteCount: limits.maximumIdentifierUTF8ByteCount
            )
        case .committedFailure(let failure):
            guard failure.authority.projectID == authority.projectID else {
                throw AgentResponseEncodingError.invalidPlan(
                    "Committed failure authority must preserve the planned projectID."
                )
            }
            try Self.validate(authority: failure.authority, limits: limits)
        }
    }

    private static func validate(
        authority: AgentProjectAuthorityCoordinate,
        limits: AgentProtocolEncodingLimits
    ) throws {
        try validateIdentity(
            authority.projectID.rawValue,
            name: "authority projectID",
            maximumByteCount: limits.maximumProjectIDUTF8ByteCount
        )
        try validate(
            authority.documentGeneration.value,
            metric: "documentGeneration",
            limits: limits
        )
        try validate(
            authority.transactionRevision.value,
            metric: "transactionRevision",
            limits: limits
        )
        try validate(
            authority.publicationSequence,
            metric: "publicationSequence",
            limits: limits
        )
        try validate(
            authority.workspaceRevision.value,
            metric: "workspaceRevision",
            limits: limits
        )
    }

    private static func validate(
        _ value: UInt64,
        metric: String,
        limits: AgentProtocolEncodingLimits
    ) throws {
        guard String(value).utf8.count <= limits.maximumScalarUTF8ByteCount else {
            throw AgentResponseEncodingError.invalidPlan(
                "\(metric) exceeds the configured scalar byte ceiling."
            )
        }
    }

    private static func validate(
        _ value: Int,
        metric: String,
        limits: AgentProtocolEncodingLimits
    ) throws {
        guard value >= 0 else {
            throw AgentResponseEncodingError.invalidPlan(
                "\(metric) must not be negative."
            )
        }
        try validate(UInt64(value), metric: metric, limits: limits)
    }

    private static func validate(
        diagnostics: [AgentSemanticDiagnostic],
        charge: SemanticResultCharge
    ) throws {
        guard UInt64(diagnostics.count) <= charge.diagnosticRecordCount else {
            throw AgentResponseEncodingError.chargeExceedsBudget(
                metric: "diagnosticRecordCount",
                actual: UInt64(diagnostics.count),
                maximum: charge.diagnosticRecordCount
            )
        }
        var messageByteCount: UInt64 = 0
        for diagnostic in diagnostics {
            let (next, overflow) = messageByteCount.addingReportingOverflow(
                UInt64(diagnostic.message.utf8.count)
            )
            guard !overflow else {
                throw AgentResponseEncodingError.chargeOverflow(
                    metric: "diagnosticStringUTF8ByteCount"
                )
            }
            messageByteCount = next
        }
        guard messageByteCount <= charge.diagnosticStringUTF8ByteCount else {
            throw AgentResponseEncodingError.chargeExceedsBudget(
                metric: "diagnosticStringUTF8ByteCount",
                actual: messageByteCount,
                maximum: charge.diagnosticStringUTF8ByteCount
            )
        }
    }

    private static func validate(
        telemetry: AgentSemanticTelemetry,
        limits: AgentProtocolEncodingLimits
    ) throws {
        try validate(telemetry.compilation.decodedValueCount, metric: "decodedValueCount", limits: limits)
        try validate(telemetry.compilation.decodedNestingDepth, metric: "decodedNestingDepth", limits: limits)
        try validate(telemetry.compilation.nodeCount, metric: "nodeCount", limits: limits)
        try validate(telemetry.compilation.edgeCount, metric: "edgeCount", limits: limits)
        try validate(telemetry.compilation.parameterCount, metric: "parameterCount", limits: limits)
        try validate(telemetry.compilation.requestedOutputCount, metric: "requestedOutputCount", limits: limits)
        try validate(
            telemetry.compilation.localOutputReferenceCount,
            metric: "localOutputReferenceCount",
            limits: limits
        )
        try validate(telemetry.compilation.expressionCount, metric: "expressionCount", limits: limits)
        try validate(telemetry.compilation.expressionDepth, metric: "expressionDepth", limits: limits)
        try validate(telemetry.compilation.expressionWork, metric: "expressionWork", limits: limits)
        try validate(telemetry.compilation.loweredCommandCount, metric: "loweredCommandCount", limits: limits)
        try validate(telemetry.compilation.expandedSourceWork, metric: "expandedSourceWork", limits: limits)
        try validate(telemetry.execution.stepCount, metric: "stepCount", limits: limits)
        try validate(telemetry.execution.commandCount, metric: "commandCount", limits: limits)
        try validate(telemetry.execution.inputSlotCount, metric: "inputSlotCount", limits: limits)
        try validate(telemetry.execution.outputSlotCount, metric: "outputSlotCount", limits: limits)
        try validate(
            telemetry.execution.generatedIdentityCount,
            metric: "generatedIdentityCount",
            limits: limits
        )
        try validate(telemetry.execution.generatedSourceWork, metric: "generatedSourceWork", limits: limits)
    }

    private static func validate(binding: AgentSemanticOutputBinding) throws {
        let compatible: Bool = switch (binding.output.kind, binding.value) {
        case (.feature, .feature):
            true
        case (.sourceBody(let role), .body(_, let valueRole, _)):
            role == valueRole
        case (.sceneNode, .sceneNode):
            true
        case (.componentDefinition, .componentDefinition):
            true
        case (.componentInstance, .componentInstance):
            true
        case (.patternArraySource, .patternArraySource):
            true
        default:
            false
        }
        guard compatible else {
            throw AgentResponseEncodingError.invalidPlan(
                "A committed output value kind does not match its requested output kind."
            )
        }
    }

    func envelope(for response: AgentResponse) throws -> AgentResponseEnvelope {
        try validate(response: response)
        return AgentResponseEnvelope(
            id: requestID,
            response: response,
            method: method
        )
    }

    private static func semanticResponse(
        method: String,
        result: AgentSemanticExecutionResult,
        id: String
    ) -> AgentResponseEnvelope {
        let response: AgentResponse = switch method {
        case "capability.invoke": .capabilityExecution(result)
        case "program.execute": .programExecution(result)
        default: .failure(EditorError(code: .commandInvalid, message: "Unsupported semantic method."))
        }
        return AgentResponseEnvelope(id: id, response: response, method: method)
    }

    private static func encodedByteCount(response: AgentResponseEnvelope) throws -> Int {
        try JSONEncoder().encode(response).count
    }

    private static func maximumAuthority(
        projectIDByteCount: Int,
        scalarByteCount: Int
    ) -> AgentProjectAuthorityCoordinate {
        AgentProjectAuthorityCoordinate(
            projectID: ProjectID(
                rawValue: String(repeating: "\"", count: projectIDByteCount)
            ),
            documentGeneration: DocumentGeneration(maximumUnsignedScalar(scalarByteCount)),
            transactionRevision: DocumentTransactionRevision(
                maximumUnsignedScalar(scalarByteCount)
            ),
            publicationSequence: maximumUnsignedScalar(scalarByteCount),
            workspaceRevision: WorkspaceRevision(maximumUnsignedScalar(scalarByteCount))
        )
    }

    private static func maximumTelemetry(
        scalarByteCount: Int
    ) -> AgentSemanticTelemetry {
        let signed = maximumSignedScalar(scalarByteCount)
        let unsigned = maximumUnsignedScalar(scalarByteCount)
        return AgentSemanticTelemetry(
            compilation: AgentSemanticTelemetry.Compilation(
                decodedValueCount: signed,
                decodedNestingDepth: signed,
                nodeCount: signed,
                edgeCount: signed,
                parameterCount: signed,
                requestedOutputCount: signed,
                localOutputReferenceCount: signed,
                expressionCount: signed,
                expressionDepth: signed,
                expressionWork: unsigned,
                loweredCommandCount: signed,
                expandedSourceWork: unsigned
            ),
            execution: AgentSemanticTelemetry.Execution(
                stepCount: signed,
                commandCount: signed,
                inputSlotCount: signed,
                outputSlotCount: signed,
                generatedIdentityCount: signed,
                generatedSourceWork: unsigned
            )
        )
    }

    private static func maximumOutput(
        identifierByteCount: Int
    ) -> AgentSemanticOutputBinding {
        let identifier = String(repeating: "\"", count: identifierByteCount)
        let output = AgentSemanticOutputReference(
            node: identifier,
            output: identifier,
            kind: .sourceBody(role: .sheet)
        )
        let uuidValue = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        return AgentSemanticOutputBinding(
            output: output,
            value: .body(
                featureID: FeatureID(uuidValue),
                role: .sheet,
                evaluatedBodyID: BodyID(uuidValue)
            )
        )
    }

    private static func validateIdentity(
        _ value: String,
        name: String,
        maximumByteCount: Int
    ) throws {
        guard !value.isEmpty,
              value.utf8.count <= maximumByteCount,
              value.trimmingCharacters(in: .whitespacesAndNewlines) == value,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw AgentResponseEncodingError.invalidPlan(
                "\(name) is empty, contains control characters, or exceeds its byte ceiling."
            )
        }
    }

    private static func intValue(_ value: UInt64, metric: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw AgentResponseEncodingError.chargeOverflow(metric: metric)
        }
        return Int(value)
    }

    private static func adding(
        _ lhs: Int,
        _ rhs: UInt64,
        metric: String
    ) throws -> Int {
        guard rhs <= UInt64(Int.max) else {
            throw AgentResponseEncodingError.chargeOverflow(metric: metric)
        }
        let (value, overflow) = lhs.addingReportingOverflow(Int(rhs))
        guard !overflow else {
            throw AgentResponseEncodingError.chargeOverflow(metric: metric)
        }
        return value
    }

    private static func adding(
        _ lhs: Int,
        _ rhs: Int,
        metric: String
    ) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw AgentResponseEncodingError.chargeOverflow(metric: metric)
        }
        return value
    }

    private static func multiplied(
        _ lhs: UInt64,
        by rhs: UInt64,
        metric: String
    ) throws -> UInt64 {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow, value <= UInt64(Int.max) else {
            throw AgentResponseEncodingError.chargeOverflow(metric: metric)
        }
        return value
    }

    private static func subtracting(
        _ lhs: Int,
        _ rhs: Int,
        metric: String
    ) throws -> Int {
        let (value, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard !overflow, value >= 0 else {
            throw AgentResponseEncodingError.invalidPlan(
                "The encoded \(metric) delta is negative."
            )
        }
        return value
    }

    private static func maximumUnsignedScalar(_ digits: Int) -> UInt64 {
        if digits >= 20 {
            return UInt64.max
        }
        var value: UInt64 = 0
        for _ in 0..<max(1, digits) {
            value = value * 10 + 9
        }
        return value
    }

    private static func maximumSignedScalar(_ digits: Int) -> Int {
        if digits >= 19 {
            return Int.max
        }
        var value = 0
        for _ in 0..<max(1, digits) {
            value = value * 10 + 9
        }
        return value
    }
}

private extension AgentResponse {
    var methodName: String? {
        switch self {
        case .capabilities: "agent.capabilities"
        case .capabilityRegistry: "agent.capabilityRegistry"
        case .status: "agent.status"
        case .sessions: "sessions.list"
        case .sessionOperation: nil
        case .cadInteractionQualityAssessment: "agent.cadInteractionQualityAssessment"
        case .command: "command.apply"
        case .batch: "command.applyBatch"
        case .domainExecution: "domain.execute"
        case .capabilityExecution: "capability.invoke"
        case .programExecution: "program.execute"
        case .parameters: "document.parameters"
        case .evaluation: "document.evaluate"
        case .measurement: "document.measure"
        case .selectionMeasurement: "selection.measure"
        case .snapResolution: "snap.resolve"
        case .constructionPlaneSummary: "document.constructionPlaneSummary"
        case .sceneGraphSnapshot: "document.sceneGraphSnapshot"
        case .viewportSnapshot: "project.viewportSnapshot"
        case .designDisplaySnapshot: "document.designDisplaySnapshot"
        case .patternArraySummary: "document.patternArraySummary"
        case .meshSummary: "document.meshSummary"
        case .meshCatalog: "project.mesh.catalog"
        case .meshPage: "project.mesh.page"
        case .meshNeighborhood: "project.mesh.neighborhood"
        case .meshEditPreview: "project.mesh.edit.preview"
        case .meshEditCommit: "project.mesh.edit.commit"
        case .makeEditable: "project.mesh.makeEditable"
        case .polySplineMeshAnalysis: "document.polySplineMeshAnalysis"
        case .sketchEntitySummary: "document.sketchEntitySummary"
        case .sketchDimensionSummary: "document.sketchDimensionSummary"
        case .selectionDimensionEvaluation: "selection.dimensionEvaluation"
        case .curveAnalysis: "document.curveAnalysis"
        case .topologySummary: "document.topologySummary"
        case .sweepEvaluationPlan: "document.sweepEvaluationPlan"
        case .booleanEvaluationPlan: "document.booleanEvaluationPlan"
        case .objectDimensionSummary: "document.objectDimensionSummary"
        case .surfaceSourceSummary: "document.surfaceSourceSummary"
        case .surfaceAnalysis: "document.surfaceAnalysis"
        case .surfaceFrames: "document.surfaceFrames"
        case .surfaceContinuitySummary: "document.surfaceContinuitySummary"
        case .surfaceBoundaryContinuityCompatibility: "document.surfaceBoundaryContinuityCompatibility"
        case .selection: "selection.selectTargets"
        case .save: "document.save"
        case .export: "document.export"
        case .committedMutation: nil
        case .failure: nil
        }
    }
}
