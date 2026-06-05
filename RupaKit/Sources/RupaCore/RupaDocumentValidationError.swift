import Foundation

public enum RupaDocumentValidationError: Error, Equatable, Sendable {
    case invalidProductMetadata(String)
}

extension RupaDocumentValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidProductMetadata(let message):
            message
        }
    }
}
