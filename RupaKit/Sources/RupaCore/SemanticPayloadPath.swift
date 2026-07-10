import Foundation

public struct SemanticPayloadPath: Codable, Hashable, Sendable {
    public var components: [SemanticPayloadPathComponent]

    public init(_ components: [SemanticPayloadPathComponent]) {
        self.components = components
    }

    public static let root = SemanticPayloadPath([])

    public func validate() throws {
        for component in components {
            switch component {
            case .key(let key):
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Semantic payload path keys must not be empty."
                    )
                }
            case .index(let index):
                guard index >= 0 else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Semantic payload path indexes must not be negative."
                    )
                }
            }
        }
    }

    public func resolve(in payload: SemanticJSONValue) throws -> SemanticJSONValue {
        var value = payload
        for component in components {
            switch (component, value) {
            case (.key(let key), .object(let object)):
                guard let next = object[key] else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Semantic payload dependency path does not resolve key \(key)."
                    )
                }
                value = next
            case (.index(let index), .array(let array)):
                guard array.indices.contains(index) else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Semantic payload dependency path index \(index) is out of bounds."
                    )
                }
                value = array[index]
            case (.key, _):
                throw DocumentValidationError.invalidProductMetadata(
                    "Semantic payload dependency path expected an object."
                )
            case (.index, _):
                throw DocumentValidationError.invalidProductMetadata(
                    "Semantic payload dependency path expected an array."
                )
            }
        }
        return value
    }
}
