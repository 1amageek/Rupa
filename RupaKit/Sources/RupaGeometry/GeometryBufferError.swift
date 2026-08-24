import Foundation

/// A typed failure raised by geometry-buffer validation, hashing, or copy accounting.
public struct GeometryBufferError: Error, Codable, Equatable, LocalizedError, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case invalidRange
        case invalidHashingLimit
        case hashingLimitExceeded
        case nonFiniteHashValue
        case inconsistentCollection
        case sizeOverflow
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
