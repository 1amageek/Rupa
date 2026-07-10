import Foundation

public struct DomainCommandPayloadError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case missingValue
        case unknownParameter
        case invalidValue
        case invalidDescriptor
    }

    public var code: Code
    public var parameterID: String?
    public var message: String

    public init(
        code: Code,
        parameterID: String? = nil,
        message: String
    ) {
        self.code = code
        self.parameterID = parameterID
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
