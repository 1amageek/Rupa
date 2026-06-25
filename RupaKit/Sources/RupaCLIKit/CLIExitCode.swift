import ArgumentParser
import Foundation
import RupaCore

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

        guard let error = error as? EditorError else {
            return .software
        }

        switch error.code {
        case .commandInvalid:
            return .usage
        case .documentOpenInApp,
             .documentGenerationMismatch,
             .sessionNotFound,
             .referenceUnresolved:
            return .data
        case .documentLoadFailed,
             .documentSaveFailed:
            return .inputOutput
        case .agentUnavailable,
             .agentConnectionFailed:
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

    public static func run(_ body: () throws -> Void) throws {
        do {
            try body()
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
