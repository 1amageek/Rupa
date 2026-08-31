import RupaProject

public struct ProjectSemanticProgramCommittedFailure: Sendable, Equatable {
    public enum Code: String, Sendable, Equatable {
        case cancelled
        case viewProjectionFailed
        case resultProjectionFailed
        case evaluatedBodyUnavailable
        case authorityValidationFailed
    }

    public enum RetryDisposition: String, Sendable, Equatable {
        case mustNotRetry
    }

    public let code: Code
    public let authority: ProjectAuthorityCoordinate
    public let retryDisposition: RetryDisposition

    public init(code: Code, authority: ProjectAuthorityCoordinate) {
        self.code = code
        self.authority = authority
        self.retryDisposition = .mustNotRetry
    }
}
