import ArgumentParser
import Foundation
import RupaCore
import RupaProjectAccess

public enum CLIExitCode: Int32, Codable, Equatable, Sendable {
    case success = 0
    case usage = 64
    case data = 65
    case inputOutput = 66
    case unavailable = 69
    case software = 70

    public static func value(for error: Error) -> CLIExitCode {
        if error is ValidationError {
            return .usage
        }
        if error is CLICommittedMutationError {
            return .data
        }
        if let error = error as? ProjectAccessError {
            switch error {
            case .invalidTarget,
                 .unsupportedProjectFormat:
                return .usage
            case .sessionMismatch,
                 .outcomeUnknown,
                 .committedMutation:
                return .data
            case .saveUnavailable:
                return .inputOutput
            case .sessionUnavailable,
                 .deadlineExceeded,
                 .authorityUnavailable:
                return .unavailable
            case .finished:
                return .software
            }
        }

        guard let error = error as? EditorError else {
            return .software
        }

        switch error.code {
        case .commandInvalid:
            return .usage
        case .documentOpenInApp,
             .documentGenerationMismatch,
             .documentTransactionRevisionMismatch,
             .workspaceRevisionMismatch,
             .sourceIdentityMismatch,
             .projectMismatch,
             .projectPublicationMismatch,
             .sessionNotFound,
             .referenceUnresolved:
            return .data
        case .documentLoadFailed,
             .documentSaveFailed:
            return .inputOutput
        case .agentUnavailable,
             .agentConnectionFailed,
             .commandUnsupported:
            return .unavailable
        case .commandFailed,
             .evaluationFailed,
             .exportFailed:
            return .software
        }
    }

    public static func exitCode(for error: Error) -> ExitCode {
        ExitCode(value(for: error).rawValue)
    }

    public static func run(_ body: () async throws -> Void) async throws {
        do {
            try await CLIProjectAccessRunner.withCommandScope(body)
        } catch {
            writeError(error)
            throw exitCode(for: error)
        }
    }

    private static func writeError(_ error: Error) {
        let message: String
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            message = errorDescription
        } else {
            message = String(describing: error)
        }
        guard let data = "\(message)\n".data(using: .utf8) else {
            return
        }
        FileHandle.standardError.write(data)
    }
}
