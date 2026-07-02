import Foundation

public struct ObjectTypeRegistry: Sendable {
    public var definitions: [ObjectTypeID: ObjectTypeDefinition]

    public static let builtIn = ObjectTypeRegistry(
        validatedBuiltInDefinitions: ObjectTypeCatalog.builtInDefinitions
    )

    public init(definitions: [ObjectTypeDefinition]) throws {
        var registeredDefinitions: [ObjectTypeID: ObjectTypeDefinition] = [:]
        for definition in definitions {
            guard registeredDefinitions[definition.id] == nil else {
                throw DocumentValidationError.invalidProductMetadata("Object type IDs must be unique.")
            }
            try definition.validate()
            registeredDefinitions[definition.id] = definition
        }
        self.definitions = registeredDefinitions
    }

    public init(registrations: [ObjectTypeRegistration]) throws {
        try self.init(definitions: registrations.map(\.definition))
    }

    private init(validatedBuiltInDefinitions definitions: [ObjectTypeDefinition]) {
        var registeredDefinitions: [ObjectTypeID: ObjectTypeDefinition] = [:]
        for definition in definitions {
            registeredDefinitions[definition.id] = definition
        }
        self.definitions = registeredDefinitions
    }

    public func definition(for id: ObjectTypeID?) -> ObjectTypeDefinition? {
        guard let id else {
            return nil
        }
        return definitions[id]
    }

    public func defaultProperties(for id: ObjectTypeID?) -> ObjectPropertySet {
        definition(for: id)?.defaultProperties ?? ObjectPropertySet()
    }

    public func defaultProperties(
        for id: ObjectTypeID?,
        ruler: RulerConfiguration
    ) -> ObjectPropertySet {
        guard let id,
              let definition = definition(for: id) else {
            return ObjectPropertySet()
        }
        let defaults = WorkspaceScaleDefaults(ruler: ruler)
        var properties = definition.defaultProperties

        for property in definition.properties {
            guard property.valueKind == .length,
                  let workspaceScaleDefault = property.workspaceScaleDefault else {
                continue
            }
            properties[property.id] = .length(workspaceScaleDefault.meters(from: defaults))
        }

        return definition.resolvedProperties(properties)
    }

    public func geometryRole(for id: ObjectTypeID?) -> ObjectDescriptor.GeometryRole? {
        definition(for: id)?.geometryRole
    }

    public func requireDefinition(for id: ObjectTypeID?) throws -> ObjectTypeDefinition {
        guard let id else {
            throw DocumentValidationError.invalidProductMetadata("Object property edits require an object type ID.")
        }
        guard let definition = definitions[id] else {
            throw DocumentValidationError.invalidProductMetadata("Object type \(id.rawValue) is not registered.")
        }
        return definition
    }

    public func validatePropertyMutation(
        typeID: ObjectTypeID?,
        propertyID: ObjectPropertyID,
        value: ObjectPropertyValue?,
        materialLibrary: MaterialLibrary
    ) throws -> ObjectTypeDefinition {
        let definition = try requireDefinition(for: typeID)
        guard let property = definition.property(for: propertyID) else {
            throw DocumentValidationError.invalidProductMetadata(
                "Object type \(definition.id.rawValue) does not define property \(propertyID.rawValue)."
            )
        }
        guard property.isEditable && property.inspectorControl != .readOnly else {
            throw DocumentValidationError.invalidProductMetadata(
                "Object property \(propertyID.rawValue) is read-only."
            )
        }
        if let value {
            try ObjectPropertySet.validate(
                value: value,
                for: property,
                materialLibrary: materialLibrary,
                allowsReadOnlyValues: false
            )
        }
        return definition
    }
}
