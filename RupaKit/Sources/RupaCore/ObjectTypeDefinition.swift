import Foundation

public struct ObjectTypeDefinition: Codable, Hashable, Identifiable, Sendable {
    public enum GeneratedRepresentationRule: Codable, Hashable, Sendable {
        case fixed(ObjectRepresentationKind)
        case lengthPropertyThreshold(
            propertyID: ObjectPropertyID,
            threshold: Double,
            defaultRepresentation: ObjectRepresentationKind,
            activeRepresentation: ObjectRepresentationKind
        )
    }

    public var id: ObjectTypeID
    public var title: String
    public var systemImage: String
    public var sourceRepresentation: ObjectRepresentationKind
    public var defaultGeneratedRepresentation: ObjectRepresentationKind
    public var generatedRepresentationRule: GeneratedRepresentationRule
    public var category: ObjectDescriptor.Category
    public var geometryRole: ObjectDescriptor.GeometryRole?
    public var properties: [ObjectPropertyDefinition]

    public init(
        id: ObjectTypeID,
        title: String,
        systemImage: String,
        representation: ObjectRepresentationKind,
        generatedRepresentation: ObjectRepresentationKind? = nil,
        generatedRepresentationRule: GeneratedRepresentationRule? = nil,
        category: ObjectDescriptor.Category,
        geometryRole: ObjectDescriptor.GeometryRole? = nil,
        properties: [ObjectPropertyDefinition] = []
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.sourceRepresentation = representation
        self.defaultGeneratedRepresentation = generatedRepresentation ?? representation
        self.generatedRepresentationRule = generatedRepresentationRule ?? .fixed(generatedRepresentation ?? representation)
        self.category = category
        self.geometryRole = geometryRole
        self.properties = properties
    }

    public var representation: ObjectRepresentationKind {
        sourceRepresentation
    }

    public var generatedRepresentation: ObjectRepresentationKind {
        defaultGeneratedRepresentation
    }

    public var defaultProperties: ObjectPropertySet {
        var values: [ObjectPropertyID: ObjectPropertyValue] = [:]
        for property in properties where values[property.id] == nil {
            values[property.id] = property.defaultValue
        }
        return ObjectPropertySet(values: values)
    }

    public func property(for id: ObjectPropertyID) -> ObjectPropertyDefinition? {
        properties.first { $0.id == id }
    }

    public func property(for binding: ObjectPropertyDefinition.RenderBinding) -> ObjectPropertyDefinition? {
        properties.first { $0.renderBinding == binding }
    }

    public func resolvedProperties(_ propertySet: ObjectPropertySet) -> ObjectPropertySet {
        var values = defaultProperties.values
        for (id, value) in propertySet.values {
            values[id] = value
        }
        return ObjectPropertySet(values: values)
    }

    public func generatedRepresentation(for propertySet: ObjectPropertySet) -> ObjectRepresentationKind {
        switch generatedRepresentationRule {
        case .fixed(let representation):
            return representation
        case .lengthPropertyThreshold(
            let propertyID,
            let threshold,
            let defaultRepresentation,
            let activeRepresentation
        ):
            guard let property = property(for: propertyID) else {
                return defaultRepresentation
            }
            let value = resolvedProperties(propertySet)
                .value(for: property.id, default: property.defaultValue)
            guard case .length(let meters) = value,
                  abs(meters) > threshold else {
                return defaultRepresentation
            }
            return activeRepresentation
        }
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Object type titles must not be empty.")
        }
        guard !systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Object type system images must not be empty.")
        }
        guard Set(properties.map(\.id)).count == properties.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Object type \(id.rawValue) property IDs must be unique."
            )
        }
        for property in properties {
            try property.validate()
        }
        switch generatedRepresentationRule {
        case .fixed:
            break
        case .lengthPropertyThreshold(let propertyID, let threshold, _, _):
            guard threshold.isFinite, threshold >= 0.0 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Object type \(id.rawValue) generated representation threshold must be finite and non-negative."
                )
            }
            guard let property = property(for: propertyID),
                  property.valueKind == .length else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Object type \(id.rawValue) generated representation rule must reference a length property."
                )
            }
        }
    }
}
