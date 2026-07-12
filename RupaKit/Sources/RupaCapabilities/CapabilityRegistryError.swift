import Foundation

public struct CapabilityRegistryError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case duplicateCapability
        case missingCapability
        case invalidDescriptor
        case versionMismatch
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
