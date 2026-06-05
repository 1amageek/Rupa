import ArgumentParser
import Foundation
import RupaCore

public enum RupaCLIExitCode: Int32, Codable, Equatable, Sendable {
    case success = 0
    case usage = 64
    case data = 65
    case inputOutput = 66
    case unavailable = 69
    case software = 70

    public static func value(for error: Error) -> RupaCLIExitCode {
        if error is ValidationError {
            return .usage
        }

        guard let error = error as? RupaError else {
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
            throw exitCode(for: error)
        }
    }
}
