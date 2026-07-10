import Foundation

public struct ManufacturingProcessCatalogError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidProfile
        case duplicateProcess
        case missingDefaultProcess
        case unsupportedProcess
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
