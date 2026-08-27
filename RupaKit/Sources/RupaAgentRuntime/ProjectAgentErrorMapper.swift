import RupaAgentProtocol
import RupaCoreTypes
import RupaKit
import RupaProject

/// Preserves project conflicts and unsupported routes as typed Agent failures.
public struct ProjectAgentErrorMapper: Sendable {
    public init() {}

    public func editorError(for error: any Error) -> EditorError {
        if let error = error as? EditorError {
            return error
        }
        if error is CancellationError {
            return EditorError(
                code: .commandInvalid,
                message: "The Agent project request was cancelled."
            )
        }
        if let error = error as? ProjectControllerError {
            let code: EditorError.Code
            switch error.code {
            case .revisionConflict:
                code = .documentTransactionRevisionMismatch
            case .historyUnavailable:
                code = .commandInvalid
            case .publicationConflict:
                code = .projectPublicationMismatch
            case .projectMismatch:
                code = .projectMismatch
            case .snapshotUnavailable:
                code = .agentUnavailable
            case .packageFailed:
                code = .documentSaveFailed
            case .evaluationFailed:
                code = .evaluationFailed
            case .sourceInvalid,
                 .sourceMismatch,
                 .transactionInvalid,
                 .productSourceFailed,
                 .cadSourceFailed,
                 .projectionFailed:
                code = .commandFailed
            }
            return EditorError(code: code, message: error.message)
        }
        if let error = error as? ProjectDomainCommandDispatchError {
            let code: EditorError.Code
            switch error.code {
            case .generationMismatch:
                code = .documentGenerationMismatch
            case .projectMismatch:
                code = .projectMismatch
            case .transactionRevisionMismatch:
                code = .documentTransactionRevisionMismatch
            case .publicationSequenceMismatch:
                code = .projectPublicationMismatch
            case .workspaceRevisionMismatch:
                code = .workspaceRevisionMismatch
            case .actionRouteMismatch:
                code = .commandInvalid
            }
            return EditorError(code: code, message: error.message)
        }
        if let error = error as? AgentCapabilityExecutionError {
            let code: EditorError.Code
            switch error.code {
            case .unsupportedRoute:
                code = .commandUnsupported
            case .staleRevision:
                code = .documentTransactionRevisionMismatch
            case .staleWorkspaceRevision:
                code = .workspaceRevisionMismatch
            case .invalidPayload, .effectMismatch:
                code = .commandInvalid
            case .invalidResult:
                code = .commandFailed
            }
            return EditorError(code: code, message: error.message)
        }
        if let error = error as? ProjectMeshReadError {
            return EditorError(
                code: Self.editorCode(for: error.code),
                message: error.message
            )
        }
        if let error = error as? ProjectMeshEditError {
            return EditorError(
                code: Self.editorCode(for: error.code),
                message: error.message
            )
        }
        if let error = error as? ProjectMakeEditableError {
            return EditorError(
                code: Self.editorCode(for: error.code),
                message: error.message
            )
        }
        if let error = error as? ProjectWorkspaceActionError {
            let code: EditorError.Code = error.code == .snapshotUnavailable
                ? .agentUnavailable
                : .commandFailed
            return EditorError(code: code, message: error.message)
        }
        return EditorError(
            code: .commandFailed,
            message: error.localizedDescription
        )
    }

    public func editorError(
        preserving primaryError: any Error,
        cleanupFailure: any Error
    ) -> EditorError {
        let primary = editorError(for: primaryError)
        return EditorError(
            code: primary.code,
            message: "\(primary.message) Export staging cleanup also failed: \(cleanupFailure.localizedDescription)"
        )
    }

    private static func editorCode(
        for code: ProjectMeshReadError.Code
    ) -> EditorError.Code {
        switch code {
        case .projectMismatch:
            .projectMismatch
        case .documentLifetimeMismatch,
             .publicationSequenceMismatch:
            .projectPublicationMismatch
        case .documentGenerationMismatch:
            .documentGenerationMismatch
        case .transactionRevisionMismatch:
            .documentTransactionRevisionMismatch
        case .workspaceRevisionMismatch:
            .workspaceRevisionMismatch
        case .sourceIdentityMismatch:
            .sourceIdentityMismatch
        case .cancelled,
             .invalidCursor,
             .invalidLimit,
             .limitExceeded,
             .sourceMissing,
             .elementNotFound,
             .invalidSource:
            .commandInvalid
        case .resultMismatch:
            .commandFailed
        }
    }

    private static func editorCode(
        for code: ProjectMeshEditError.Code
    ) -> EditorError.Code {
        switch code {
        case .projectMismatch:
            .projectMismatch
        case .documentLifetimeMismatch,
             .publicationSequenceMismatch:
            .projectPublicationMismatch
        case .documentGenerationMismatch:
            .documentGenerationMismatch
        case .transactionRevisionMismatch:
            .documentTransactionRevisionMismatch
        case .workspaceRevisionMismatch:
            .workspaceRevisionMismatch
        case .sourceIdentityMismatch:
            .sourceIdentityMismatch
        case .cancelled,
             .invalidPlan,
             .invalidSource,
             .sourceMissing:
            .commandInvalid
        case .resultMismatch:
            .commandFailed
        }
    }

    private static func editorCode(
        for code: ProjectMakeEditableError.Code
    ) -> EditorError.Code {
        switch code {
        case .projectMismatch:
            .projectMismatch
        case .documentLifetimeMismatch,
             .publicationSequenceMismatch:
            .projectPublicationMismatch
        case .documentGenerationMismatch:
            .documentGenerationMismatch
        case .transactionRevisionMismatch:
            .documentTransactionRevisionMismatch
        case .workspaceRevisionMismatch:
            .workspaceRevisionMismatch
        case .sourceIdentityMismatch:
            .sourceIdentityMismatch
        case .cancelled,
             .invalidRequest,
             .sourceMissing,
             .representationMissing,
             .representationMismatch,
             .duplicateIdentity,
             .nonCADModelingSource,
             .invalidSource:
            .commandInvalid
        case .resultMismatch:
            .commandFailed
        }
    }
}
