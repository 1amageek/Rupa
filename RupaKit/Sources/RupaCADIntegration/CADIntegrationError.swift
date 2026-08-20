import Foundation

public struct CADIntegrationError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case unsupportedReference
        @available(*, deprecated, message: "Use sourceUnavailable.")
        case documentMismatch
        case sourceUnavailable
        case duplicateSource
        case bodyUnavailable
        case invalidMesh
        case unsupportedFidelity
        case invalidConfiguration
        case invalidEvaluationResult
        case evaluationFailed
        case sourceRevisionConflict
    }

    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
