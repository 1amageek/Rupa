public enum ReferenceValidationErrorCode: String, Codable, Equatable, Sendable {
    case invalidIdentity
    case invalidShape
    case documentMismatch
}
