import Foundation

public struct MeshSourcePresentationPickError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidIdentity
        case identityOverflow
        case duplicateOccurrence
        case duplicateNavigationMapping
        case missingNavigation
        case staleNavigation
        case unknownIdentity
        case staleSnapshot
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
