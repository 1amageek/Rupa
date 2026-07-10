import Foundation

public struct ReferenceValidationError: Error, Codable, Equatable, Sendable, LocalizedError {
    public var code: ReferenceValidationErrorCode
    public var message: String

    public init(code: ReferenceValidationErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
