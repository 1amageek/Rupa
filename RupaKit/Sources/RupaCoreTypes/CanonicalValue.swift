import Foundation

public indirect enum CanonicalValue: Codable, Equatable, Hashable, Sendable {
    case object([String: CanonicalValue])
    case array([CanonicalValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let object = try Self.decodeObject(from: decoder) {
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
            self = .number(value)
            return
        }
        if let value = try Self.decodeString(from: container) {
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
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for key in object.keys.sorted() {
                guard let codingKey = DynamicCodingKey(stringValue: key) else {
                    continue
                }
                try container.encode(object[key], forKey: codingKey)
            }
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case .string(let value):
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
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    public func validate() throws {
        switch self {
        case .object(let object):
            for key in object.keys {
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Canonical object keys must not be empty."
                    )
                }
            }
            for value in object.values {
                try value.validate()
            }
        case .array(let array):
            for value in array {
                try value.validate()
            }
        case .number(let value):
            guard value.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Canonical numbers must be finite."
                )
            }
        case .string, .bool, .null:
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
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
