import Foundation

/// Every failure materializing the responsiveness fixture as a project package
/// can report, carrying the stage that failed.
public struct ResponsivenessFixtureDocumentError: Error, Equatable, Sendable,
    CustomStringConvertible
{
    public enum Code: String, Equatable, Sendable, Codable {
        case documentConstructionFailed
        case documentInvalid
        case productSourceEncodingFailed
        case packageConstructionFailed
        case packageWriteFailed
        case writtenPackageDiffersFromFixture
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String {
        "\(code.rawValue): \(message)"
    }
}
