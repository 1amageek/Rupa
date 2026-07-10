import Foundation

public struct DomainRegistryError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case duplicateNamespace
        case duplicateCapability
        case duplicateDecoder
        case duplicateValidator
        case duplicateCommandLowering
        case duplicateProjectionRepairProvider
        case duplicateSimulationAdapter
        case missingNamespace
        case missingCapability
        case missingCommandLowering
        case missingProjectionRepairProvider
        case missingSimulationAdapter
        case invalidRegistration
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
