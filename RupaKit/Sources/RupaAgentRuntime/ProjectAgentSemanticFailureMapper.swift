import RupaAgentProtocol
import RupaCoreTypes
import RupaDomainFoundation
import RupaProject

/// Classifies failures before project publication without serializing messages.
struct ProjectAgentSemanticFailureMapper: Sendable {
    func failure(
        for error: any Error
    ) -> AgentSemanticPrepublicationFailure {
        if error is CancellationError {
            return failure(stage: .cancelled, code: "cancelled")
        }
        if let error = error as? SemanticCompilationError {
            return compilationFailure(error)
        }
        if let error = error as? AgentSemanticRequestError {
            return failure(
                stage: .compilationRejected,
                code: DomainCapabilityErrorCode(rawValue: error.code.rawValue)
            )
        }
        if let error = error as? ProjectControllerError {
            return controllerFailure(error)
        }
        if let error = error as? EditorError {
            return editorFailure(error)
        }
        return failure(stage: .executionRejected, code: "executionRejected")
    }

    func responsePlanRejected() -> AgentSemanticPrepublicationFailure {
        failure(stage: .responsePlanRejected, code: "responsePlanRejected")
    }

    private func compilationFailure(
        _ error: SemanticCompilationError
    ) -> AgentSemanticPrepublicationFailure {
        switch error {
        case .cancelled:
            return failure(stage: .cancelled, code: "cancelled")
        case .loweringFailed(_, _, let code, _):
            return failure(stage: .compilationRejected, code: code)
        case .unsupportedSchema:
            return failure(stage: .compilationRejected, code: "unsupportedSchema")
        case .unknownOperation:
            return failure(stage: .compilationRejected, code: "unknownOperation")
        case .unsupportedOperationVersion:
            return failure(stage: .compilationRejected, code: "unsupportedOperationVersion")
        case .emptyProgram:
            return failure(stage: .compilationRejected, code: "emptyProgram")
        case .invalidIdentifier:
            return failure(stage: .compilationRejected, code: "invalidIdentifier")
        case .directLocalReference:
            return failure(stage: .compilationRejected, code: "directLocalReference")
        case .directOutputMissing:
            return failure(stage: .compilationRejected, code: "directOutputMissing")
        case .duplicateDirectOutput:
            return failure(stage: .compilationRejected, code: "duplicateDirectOutput")
        case .duplicateNode:
            return failure(stage: .compilationRejected, code: "duplicateNode")
        case .duplicateOutput:
            return failure(stage: .compilationRejected, code: "duplicateOutput")
        case .missingArgument:
            return failure(stage: .compilationRejected, code: "missingArgument")
        case .unknownArgument:
            return failure(stage: .compilationRejected, code: "unknownArgument")
        case .invalidArgument:
            return failure(stage: .compilationRejected, code: "invalidArgument")
        case .missingParameter:
            return failure(stage: .compilationRejected, code: "missingParameter")
        case .invalidParameter:
            return failure(stage: .compilationRejected, code: "invalidParameter")
        case .parameterTypeMismatch:
            return failure(stage: .compilationRejected, code: "parameterTypeMismatch")
        case .sourceReferenceUnavailable:
            return failure(stage: .compilationRejected, code: "sourceReferenceUnavailable")
        case .sourceReferenceTypeMismatch:
            return failure(stage: .compilationRejected, code: "sourceReferenceTypeMismatch")
        case .localReferenceNodeMissing:
            return failure(stage: .compilationRejected, code: "localReferenceNodeMissing")
        case .localReferenceOutputMissing:
            return failure(stage: .compilationRejected, code: "localReferenceOutputMissing")
        case .localReferenceSelf:
            return failure(stage: .compilationRejected, code: "localReferenceSelf")
        case .localReferenceKindMismatch:
            return failure(stage: .compilationRejected, code: "localReferenceKindMismatch")
        case .requestedOutputNodeMissing:
            return failure(stage: .compilationRejected, code: "requestedOutputNodeMissing")
        case .requestedOutputMissing:
            return failure(stage: .compilationRejected, code: "requestedOutputMissing")
        case .requestedOutputKindMismatch:
            return failure(stage: .compilationRejected, code: "requestedOutputKindMismatch")
        case .duplicateRequestedOutput:
            return failure(stage: .compilationRejected, code: "duplicateRequestedOutput")
        case .graphCycle:
            return failure(stage: .compilationRejected, code: "graphCycle")
        case .routeIneligible:
            return failure(stage: .compilationRejected, code: "routeIneligible")
        case .effectIneligible:
            return failure(stage: .compilationRejected, code: "effectIneligible")
        case .aggregateEffectIneligible:
            return failure(stage: .compilationRejected, code: "aggregateEffectIneligible")
        case .invalidOperationCost:
            return failure(stage: .compilationRejected, code: "invalidOperationCost")
        case .limitExceeded:
            return failure(stage: .compilationRejected, code: "limitExceeded")
        case .arithmeticInvalid:
            return failure(stage: .compilationRejected, code: "arithmeticInvalid")
        case .lowererContractViolation:
            return failure(stage: .compilationRejected, code: "lowererContractViolation")
        case .preparedPlanInvalid:
            return failure(stage: .compilationRejected, code: "preparedPlanInvalid")
        }
    }

    private func controllerFailure(
        _ error: ProjectControllerError
    ) -> AgentSemanticPrepublicationFailure {
        switch error.code {
        case .revisionConflict:
            return failure(stage: .authorityRejected, code: "transactionRevisionMismatch")
        case .documentGenerationConflict:
            return failure(stage: .authorityRejected, code: "documentGenerationMismatch")
        case .workspaceRevisionConflict:
            return failure(stage: .authorityRejected, code: "workspaceRevisionMismatch")
        case .publicationConflict:
            return failure(stage: .authorityRejected, code: "publicationSequenceMismatch")
        case .projectMismatch:
            return failure(stage: .authorityRejected, code: "projectMismatch")
        case .evaluationFailed:
            return failure(stage: .evaluationRejected, code: "evaluationFailed")
        case .resultLimitExceeded:
            return failure(stage: .executionRejected, code: "resultLimitExceeded")
        case .sourceInvalid,
             .sourceMismatch,
             .transactionInvalid,
             .historyUnavailable,
             .productSourceFailed,
             .cadSourceFailed,
             .projectionFailed,
             .packageFailed,
             .snapshotUnavailable:
            return failure(stage: .executionRejected, code: "executionRejected")
        }
    }

    private func editorFailure(
        _ error: EditorError
    ) -> AgentSemanticPrepublicationFailure {
        switch error.code {
        case .projectMismatch:
            return failure(stage: .authorityRejected, code: "projectMismatch")
        case .documentGenerationMismatch:
            return failure(stage: .authorityRejected, code: "documentGenerationMismatch")
        case .documentTransactionRevisionMismatch:
            return failure(stage: .authorityRejected, code: "transactionRevisionMismatch")
        case .projectPublicationMismatch:
            return failure(stage: .authorityRejected, code: "publicationSequenceMismatch")
        case .workspaceRevisionMismatch:
            return failure(stage: .authorityRejected, code: "workspaceRevisionMismatch")
        case .sessionNotFound,
             .documentOpenInApp,
             .agentUnavailable:
            return failure(stage: .authorityRejected, code: "sessionUnavailable")
        case .evaluationFailed:
            return failure(stage: .evaluationRejected, code: "evaluationFailed")
        case .agentConnectionFailed,
             .documentLoadFailed,
             .documentSaveFailed,
             .sourceIdentityMismatch,
             .commandInvalid,
             .commandUnsupported,
             .commandFailed,
             .referenceUnresolved,
             .exportFailed:
            return failure(stage: .executionRejected, code: "executionRejected")
        }
    }

    private func failure(
        stage: AgentSemanticPrepublicationFailure.Stage,
        code: DomainCapabilityErrorCode
    ) -> AgentSemanticPrepublicationFailure {
        AgentSemanticPrepublicationFailure(stage: stage, code: code)
    }
}
