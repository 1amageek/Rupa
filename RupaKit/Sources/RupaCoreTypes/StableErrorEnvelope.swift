import Foundation

/// Transport-neutral error data with a stable code and canonical structured details.
public struct StableErrorEnvelope: Error, Codable, Equatable, LocalizedError, Sendable {
    public let code: StableErrorCode
    public let message: String
    public let details: CanonicalValue?

    public init(
        code: StableErrorCode,
        message: String,
        details: CanonicalValue? = nil
    ) throws {
        try code.validate()
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              message.utf8.count <= 64 * 1_024 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Stable error messages must be non-empty and at most 64 KiB."
            )
        }
        try details?.validate()
        self.code = code
        self.message = message
        self.details = details
    }

    public init(editorError: EditorError, details: CanonicalValue? = nil) throws {
        try self.init(
            code: StableErrorCode(rawValue: editorError.code.rawValue),
            message: editorError.message,
            details: details
        )
    }

    public var errorDescription: String? {
        message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            code: container.decode(StableErrorCode.self, forKey: .code),
            message: container.decode(String.self, forKey: .message),
            details: container.decodeIfPresent(CanonicalValue.self, forKey: .details)
        )
    }
}
