import Foundation

public struct DesignDocumentProjectBridgeError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidDocument
        case unknownChild
        case multipleParents
        case invalidTransform
        case unresolvedGeometry
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
