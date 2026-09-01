import RupaAgentProtocol
import RupaAutomation
import RupaDomainFoundation
import RupaKit
import RupaProject

/// Losslessly maps project semantic receipts to the transport-neutral Agent DTOs.
public struct ProjectAgentSemanticResultProjector: Sendable {
    public init() {}

    public func project(
        _ result: ProjectSemanticProgramResult
    ) -> AgentSemanticExecutionResult {
        switch result {
        case .preview(let preview):
            return .success(
                .preview(
                    AgentSemanticPreviewReceipt(
                        authority: AgentProjectAuthorityCoordinate(preview.authority),
                        proposedDocumentGeneration: preview.proposedDocumentGeneration,
                        proposedTransactionRevision: preview.proposedTransactionRevision,
                        diagnostics: preview.diagnostics.map(AgentSemanticDiagnostic.init),
                        telemetry: AgentSemanticTelemetry(preview.telemetry)
                    )
                )
            )
        case .committed(let commit):
            return .success(
                .committed(
                    AgentSemanticCommitReceipt(
                        authority: AgentProjectAuthorityCoordinate(commit.authority),
                        outputs: commit.outputs.map(AgentSemanticOutputBinding.init),
                        diagnostics: commit.diagnostics.map(AgentSemanticDiagnostic.init),
                        telemetry: AgentSemanticTelemetry(commit.telemetry)
                    )
                )
            )
        case .committedFailure(let failure):
            return .committedFailure(
                AgentSemanticCommittedFailure(
                    code: AgentSemanticCommittedFailure.Code(failure.code),
                    authority: AgentProjectAuthorityCoordinate(failure.authority)
                )
            )
        }
    }
}

private extension AgentProjectAuthorityCoordinate {
    init(_ value: ProjectAuthorityCoordinate) {
        self.init(
            projectID: value.projectID,
            documentGeneration: value.documentGeneration,
            transactionRevision: value.transactionRevision,
            publicationSequence: value.publicationSequence,
            workspaceRevision: value.workspaceRevision
        )
    }
}

private extension AgentSemanticDiagnostic {
    init(_ value: ProjectSemanticDiagnostic) {
        self.init(severity: value.severity, code: value.code, message: value.message)
    }
}

private extension AgentSemanticTelemetry {
    init(_ value: ProjectSemanticTelemetry) {
        self.init(
            compilation: Compilation(value.compilation),
            execution: Execution(value.execution)
        )
    }
}

private extension AgentSemanticTelemetry.Compilation {
    init(_ value: SemanticCompilationTelemetry) {
        self.init(
            decodedValueCount: value.decodedValueCount,
            decodedNestingDepth: value.decodedNestingDepth,
            nodeCount: value.nodeCount,
            edgeCount: value.edgeCount,
            parameterCount: value.parameterCount,
            requestedOutputCount: value.requestedOutputCount,
            localOutputReferenceCount: value.localOutputReferenceCount,
            expressionCount: value.expressionCount,
            expressionDepth: value.expressionDepth,
            expressionWork: value.expressionWork,
            loweredCommandCount: value.loweredCommandCount,
            expandedSourceWork: value.expandedSourceWork
        )
    }
}

private extension AgentSemanticTelemetry.Execution {
    init(_ value: PreparedAutomationExecutionTelemetry) {
        self.init(
            stepCount: value.stepCount,
            commandCount: value.commandCount,
            inputSlotCount: value.inputSlotCount,
            outputSlotCount: value.outputSlotCount,
            generatedIdentityCount: value.generatedIdentityCount,
            generatedSourceWork: value.generatedSourceWork
        )
    }
}

private extension AgentSemanticOutputBinding {
    init(_ value: ProjectSemanticOutputBinding) {
        self.init(
            output: AgentSemanticOutputReference(value.output),
            value: Value(value.value)
        )
    }
}

private extension AgentSemanticOutputBinding.Value {
    init(_ value: ProjectSemanticOutputBinding.Value) {
        self = switch value {
        case .feature(let id):
            .feature(id)
        case .body(let featureID, let role, let evaluatedBodyID):
            .body(
                featureID: featureID,
                role: role,
                evaluatedBodyID: evaluatedBodyID
            )
        case .sceneNode(let id):
            .sceneNode(id)
        case .componentDefinition(let id):
            .componentDefinition(id)
        case .componentInstance(let id):
            .componentInstance(id)
        case .patternArraySource(let id):
            .patternArraySource(id)
        }
    }
}

private extension AgentSemanticCommittedFailure.Code {
    init(_ value: ProjectSemanticProgramCommittedFailure.Code) {
        self = switch value {
        case .cancelled: .cancelled
        case .viewProjectionFailed: .viewProjectionFailed
        case .resultProjectionFailed: .resultProjectionFailed
        case .evaluatedBodyUnavailable: .evaluatedBodyUnavailable
        case .authorityValidationFailed: .authorityValidationFailed
        }
    }
}
