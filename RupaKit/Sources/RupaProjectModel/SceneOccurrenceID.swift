import Foundation

public struct SceneOccurrenceID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public var description: String {
        rawValue
    }

    public func validate() throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProjectModelError(code: .invalidIdentity, message: "Scene occurrence IDs must not be empty.")
        }
    }
}
