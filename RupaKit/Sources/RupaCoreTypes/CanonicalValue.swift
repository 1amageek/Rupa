import Foundation

public indirect enum CanonicalValue: Codable, Equatable, Hashable, Sendable {
    case object([String: CanonicalValue])
    case array([CanonicalValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        guard decoder.codingPath.count <= 128 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Canonical values must not exceed 128 levels."
                )
            )
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let object = try Self.decodeObject(from: decoder) {
            try Self.validateObjectKeys(object.keys)
            self = .object(object)
            return
        }
        if let array = try Self.decodeArray(from: decoder) {
            self = .array(array)
            return
        }
        if let value = try Self.decodeBool(from: container) {
            self = .bool(value)
            return
        }
        if let value = try Self.decodeDouble(from: container) {
            guard value.isFinite else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Canonical numbers must be finite."
                )
            }
            self = .number(value == 0 ? 0 : value)
            return
        }
        if let value = try Self.decodeString(from: container) {
            do {
                try Self.validateString(value)
            } catch {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Canonical strings must not exceed 16 MiB of UTF-8 data.",
                        underlyingError: error
                    )
                )
            }
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported canonical value."
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let object):
            do {
                try Self.validateObjectKeys(object.keys)
            } catch {
                throw EncodingError.invalidValue(
                    object,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Canonical object keys are invalid.",
                        underlyingError: error
                    )
                )
            }
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in object.sorted(by: { $0.key < $1.key }) {
                try container.encode(value, forKey: DynamicCodingKey(key))
            }
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case .string(let value):
            do {
                try Self.validateString(value)
            } catch {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Canonical strings must not exceed 16 MiB of UTF-8 data.",
                        underlyingError: error
                    )
                )
            }
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Canonical numbers must be finite."
                    )
                )
            }
            var container = encoder.singleValueContainer()
            try container.encode(value == 0 ? 0 : value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    public func validate() throws {
        var remainingNodeCount = 1_000_000
        try validate(depth: 0, remainingNodeCount: &remainingNodeCount)
    }

    private func validate(
        depth: Int,
        remainingNodeCount: inout Int
    ) throws {
        guard depth <= 128, remainingNodeCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Canonical values exceed the supported depth or node-count limit."
            )
        }
        remainingNodeCount -= 1

        switch self {
        case .object(let object):
            try Self.validateObjectKeys(object.keys)
            for value in object.values {
                try value.validate(
                    depth: depth + 1,
                    remainingNodeCount: &remainingNodeCount
                )
            }
        case .array(let array):
            for value in array {
                try value.validate(
                    depth: depth + 1,
                    remainingNodeCount: &remainingNodeCount
                )
            }
        case .number(let value):
            guard value.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Canonical numbers must be finite."
                )
            }
        case .string(let value):
            try Self.validateString(value)
        case .bool, .null:
            break
        }
    }

    public func canonicalJSONData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    private static func decodeObject(from decoder: Decoder) throws -> [String: CanonicalValue]? {
        do {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var object: [String: CanonicalValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(CanonicalValue.self, forKey: key)
            }
            return object
        } catch DecodingError.typeMismatch {
            return nil
        } catch DecodingError.valueNotFound {
            return nil
        } catch DecodingError.keyNotFound {
            return nil
        }
    }

    private static func decodeArray(from decoder: Decoder) throws -> [CanonicalValue]? {
        do {
            var container = try decoder.unkeyedContainer()
            var values: [CanonicalValue] = []
            while !container.isAtEnd {
                values.append(try container.decode(CanonicalValue.self))
            }
            return values
        } catch DecodingError.typeMismatch {
            return nil
        } catch DecodingError.valueNotFound {
            return nil
        }
    }

    private static func decodeBool(from container: SingleValueDecodingContainer) throws -> Bool? {
        do {
            return try container.decode(Bool.self)
        } catch DecodingError.typeMismatch {
            return nil
        }
    }

    private static func decodeDouble(from container: SingleValueDecodingContainer) throws -> Double? {
        do {
            return try container.decode(Double.self)
        } catch DecodingError.typeMismatch {
            return nil
        }
    }

    private static func decodeString(from container: SingleValueDecodingContainer) throws -> String? {
        do {
            return try container.decode(String.self)
        } catch DecodingError.typeMismatch {
            return nil
        }
    }

    private static func validateObjectKeys<Keys: Sequence>(_ keys: Keys) throws
    where Keys.Element == String {
        for key in keys {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty,
                  trimmedKey == key,
                  key.utf8.count <= StableTypeValidation.maximumIdentifierByteCount,
                  key.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0)
                  }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Canonical object keys must be non-empty, unpadded, control-free, and bounded."
                )
            }
        }
    }

    private static func validateString(_ value: String) throws {
        guard value.utf8.count <= 16 * 1_024 * 1_024 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Canonical strings must not exceed 16 MiB of UTF-8 data."
            )
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
