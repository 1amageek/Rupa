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
}
