import Foundation

public struct MeshSourceID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public init() {
        self.init(rawValue: UUID().uuidString)
    }

    public var description: String {
        rawValue
    }

    public func validate() throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshSourceError(code: .invalidIdentity, message: "Mesh source IDs must not be empty.")
        }
    }
}
