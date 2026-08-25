import Foundation

public struct ProjectPackageError: Error, Equatable, LocalizedError, Sendable {
    public enum Code: String, Equatable, Sendable {
        case invalidManifest
        case invalidEntryPath
        case duplicateEntry
        case missingEntry
        case unsupportedSchema
        case unsupportedVersion
        case unsupportedFeature
        case resourceLimitExceeded
        case integrityMismatch
        case malformedArchive
        case invalidSource
        case ioFailure
        case atomicSaveFailure
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
