import Foundation

public struct CapabilityID: RawRepresentable, Codable, Hashable, Sendable,
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
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard !trimmed.isEmpty,
              trimmed == rawValue,
              components.count >= 2,
              components.allSatisfy({ !$0.isEmpty }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Capability IDs must be non-empty qualified identifiers."
            )
        }
    }
}
