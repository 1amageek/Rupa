import Foundation

public struct ProjectSemanticProgramError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidProjectionPlan
        case resultBudgetExceeded
        case executionReceiptMissing
        case requestedOutputMissing
        case requestedOutputMismatch
        case evaluatedBodyUnavailable
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
