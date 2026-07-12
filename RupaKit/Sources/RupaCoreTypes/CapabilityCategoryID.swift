import Foundation

public struct CapabilityCategoryID: RawRepresentable, Codable, Hashable, Sendable,
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
        guard !trimmed.isEmpty, trimmed == rawValue else {
            throw EditorError(
                code: .commandInvalid,
                message: "Capability category IDs must not be empty or padded."
            )
        }
    }
}
