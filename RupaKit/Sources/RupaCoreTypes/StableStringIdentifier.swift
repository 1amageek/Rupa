import Foundation

/// A persisted identifier whose textual representation is stable across processes.
public protocol StableStringIdentifier: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible where RawValue == String,
    StringLiteralType == String {
    static var identityName: String { get }
    static var requiresQualifiedName: Bool { get }

    init(rawValue: String)
}

public extension StableStringIdentifier {
    static var requiresQualifiedName: Bool {
        false
    }

    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    init(validating rawValue: String) throws {
        self.init(rawValue: rawValue)
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        rawValue
    }

    func validate() throws {
        try StableTypeValidation.validateIdentifier(
            rawValue,
            name: Self.identityName,
            requiresQualifiedName: Self.requiresQualifiedName
        )
    }
}

enum StableTypeValidation {
    static let maximumIdentifierByteCount = 1_024

    static func validateIdentifier(
        _ value: String,
        name: String,
        requiresQualifiedName: Bool = false
    ) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == value,
              value.utf8.count <= maximumIdentifierByteCount,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(name) must be non-empty, unpadded, control-free "
                    + "identifiers of at most \(maximumIdentifierByteCount) UTF-8 bytes."
            )
        }

        if requiresQualifiedName {
            let components = value.split(separator: ".", omittingEmptySubsequences: false)
            guard components.count >= 2,
                  components.allSatisfy({ component in
                      let componentValue = String(component)
                      return !componentValue.isEmpty
                          && componentValue.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ) == componentValue
                  }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(name) must contain at least two non-empty, "
                        + "unpadded components."
                )
            }
        }
    }
}
