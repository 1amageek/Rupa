import Foundation

public enum DocumentValidationError: Error, Equatable, Sendable {
    case invalidProductMetadata(String)
}

extension DocumentValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidProductMetadata(let message):
            message
        }
    }
}
