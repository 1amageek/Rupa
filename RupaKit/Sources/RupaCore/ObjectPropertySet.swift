import Foundation

public struct ObjectPropertySet: Codable, Hashable, Sendable {
    public var values: [ObjectPropertyID: ObjectPropertyValue]

    public init(values: [ObjectPropertyID: ObjectPropertyValue] = [:]) {
        self.values = values
    }

    public subscript(id: ObjectPropertyID) -> ObjectPropertyValue? {
        get {
            values[id]
        }
        set {
            values[id] = newValue
        }
    }

    public func value(for id: ObjectPropertyID, default defaultValue: ObjectPropertyValue) -> ObjectPropertyValue {
        values[id] ?? defaultValue
    }

    public func merging(_ overrides: ObjectPropertySet) -> ObjectPropertySet {
        var mergedValues = values
        for (id, value) in overrides.values {
            mergedValues[id] = value
        }
        return ObjectPropertySet(values: mergedValues)
    }

    public func validate() throws {
        for (id, value) in values {
            try value.validate(id: id)
        }
    }

    public func validate(
        against definition: ObjectTypeDefinition,
        materialLibrary: MaterialLibrary? = nil,
        allowsReadOnlyValues: Bool = true
    ) throws {
        for (id, value) in values {
            guard let property = definition.property(for: id) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Object type \(definition.id.rawValue) does not define property \(id.rawValue)."
                )
            }
            try Self.validate(
                value: value,
                for: property,
                materialLibrary: materialLibrary,
                allowsReadOnlyValues: allowsReadOnlyValues
            )
        }
    }

    public static func validate(
        value: ObjectPropertyValue,
        for property: ObjectPropertyDefinition,
        materialLibrary: MaterialLibrary? = nil,
        allowsReadOnlyValues: Bool = true
    ) throws {
        guard allowsReadOnlyValues || property.isEditable && property.inspectorControl != .readOnly else {
            throw DocumentValidationError.invalidProductMetadata(
                "Object property \(property.id.rawValue) is read-only."
            )
        }
        guard value.valueKind == property.valueKind else {
            throw DocumentValidationError.invalidProductMetadata(
                "Object property \(property.id.rawValue) value kind must match its definition."
            )
        }
        try value.validate(id: property.id)
        if let numericRange = property.numericRange {
            try validateRange(value, range: numericRange, id: property.id)
        }
        if case .material(let materialID) = value,
           let materialID,
           let materialLibrary,
           materialLibrary.materials[materialID] == nil {
            throw DocumentValidationError.invalidProductMetadata(
                "Object property \(property.id.rawValue) references a missing material."
            )
        }
    }

    private static func validateRange(
        _ value: ObjectPropertyValue,
        range: ObjectPropertyDefinition.NumericRange,
        id: ObjectPropertyID
    ) throws {
        let numericValue: Double?
        switch value {
        case .length(let value), .number(let value), .angle(let value):
            numericValue = value
        case .integer(let value):
            numericValue = Double(value)
        case .boolean, .text, .material:
            numericValue = nil
        }
        guard let numericValue else {
            return
        }
        guard numericValue >= range.lowerBound,
              numericValue <= range.upperBound else {
            throw DocumentValidationError.invalidProductMetadata(
                "Object property \(id.rawValue) is outside its allowed range."
            )
        }
    }
}
