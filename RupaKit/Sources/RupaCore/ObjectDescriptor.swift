import Foundation
import SwiftCAD

public struct ObjectDescriptor: Codable, Hashable, Sendable {
    public enum Category: String, Codable, Sendable {
        case group
        case componentInstance
        case body
        case sketch
        case construction
        case annotation
        case camera
        case light

        public var title: String {
            switch self {
            case .group:
                "Group"
            case .componentInstance:
                "Component Instance"
            case .body:
                "Body"
            case .sketch:
                "Sketch"
            case .construction:
                "Construction"
            case .annotation:
                "Annotation"
            case .camera:
                "Camera"
            case .light:
                "Light"
            }
        }
    }

    public enum GeometryRole: String, Codable, Sendable {
        case solid
        case surface
        case mesh
        case curve
        case sketchProfile
        case construction
        case text

        public var title: String {
            switch self {
            case .solid:
                "Solid"
            case .surface:
                "Surface"
            case .mesh:
                "Mesh"
            case .curve:
                "Curve"
            case .sketchProfile:
                "Sketch Profile"
            case .construction:
                "Construction"
            case .text:
                "Text"
            }
        }
    }

    public var category: Category
    public var geometryRole: GeometryRole?
    public var typeID: ObjectTypeID?
    public var properties: ObjectPropertySet
    public var sourceFeatureID: FeatureID?
    public var sourceSection: BodySourceSectionReference?
    public var componentInstanceID: ComponentInstanceID?

    public init(
        category: Category,
        geometryRole: GeometryRole? = nil,
        typeID: ObjectTypeID? = nil,
        properties: ObjectPropertySet = ObjectPropertySet(),
        sourceFeatureID: FeatureID? = nil,
        sourceSection: BodySourceSectionReference? = nil,
        componentInstanceID: ComponentInstanceID? = nil
    ) {
        self.category = category
        self.geometryRole = geometryRole
        self.typeID = typeID
        self.properties = properties
        self.sourceFeatureID = sourceFeatureID
        self.sourceSection = sourceSection
        self.componentInstanceID = componentInstanceID
    }

    public static func group() -> ObjectDescriptor {
        ObjectDescriptor(category: .group)
    }

    public static func sketch(
        featureID: FeatureID,
        typeID: ObjectTypeID? = nil,
        geometryRole: GeometryRole = .sketchProfile,
        properties: ObjectPropertySet = ObjectPropertySet(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> ObjectDescriptor {
        let resolvedProperties = objectRegistry.defaultProperties(for: typeID).merging(properties)
        return ObjectDescriptor(
            category: .sketch,
            geometryRole: objectRegistry.geometryRole(for: typeID) ?? geometryRole,
            typeID: typeID,
            properties: resolvedProperties,
            sourceFeatureID: featureID
        )
    }

    public static func body(
        featureID: FeatureID,
        sourceSection: BodySourceSectionReference?,
        typeID: ObjectTypeID?,
        geometryRole: GeometryRole = .solid,
        properties: ObjectPropertySet = ObjectPropertySet(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> ObjectDescriptor {
        let resolvedProperties = objectRegistry.defaultProperties(for: typeID).merging(properties)
        return ObjectDescriptor(
            category: .body,
            geometryRole: objectRegistry.geometryRole(for: typeID) ?? geometryRole,
            typeID: typeID,
            properties: resolvedProperties,
            sourceFeatureID: featureID,
            sourceSection: sourceSection
        )
    }

    public static func componentInstance(_ id: ComponentInstanceID) -> ObjectDescriptor {
        ObjectDescriptor(
            category: .componentInstance,
            componentInstanceID: id
        )
    }

    public static func construction() -> ObjectDescriptor {
        ObjectDescriptor(
            category: .construction,
            geometryRole: .construction
        )
    }

    public static func annotation() -> ObjectDescriptor {
        ObjectDescriptor(category: .annotation)
    }

    public func validate() throws {
        switch category {
        case .group:
            guard geometryRole == nil,
                  typeID == nil,
                  properties.values.isEmpty,
                  sourceFeatureID == nil,
                  sourceSection == nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Group objects must not contain geometry or source references."
                )
            }
        case .componentInstance:
            guard componentInstanceID != nil,
                  typeID == nil,
                  properties.values.isEmpty,
                  sourceFeatureID == nil,
                  sourceSection == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instance objects must contain exactly one component instance reference."
                )
            }
        case .body:
            guard geometryRole != nil,
                  sourceFeatureID != nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Body objects must contain geometry role and source feature references."
                )
            }
            try properties.validate()
        case .sketch:
            guard geometryRole == .sketchProfile || geometryRole == .curve,
                  sourceFeatureID != nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Sketch objects must contain one sketch profile or curve source reference."
                )
            }
            try properties.validate()
        case .construction:
            guard geometryRole == .construction,
                  typeID == nil,
                  properties.values.isEmpty,
                  sourceFeatureID == nil,
                  sourceSection == nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction objects must not contain feature or component references."
                )
            }
        case .annotation:
            guard componentInstanceID == nil,
                  sourceSection == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Annotation objects must not contain profile or component references."
                )
            }
            try properties.validate()
        case .camera, .light:
            guard typeID == nil,
                  properties.values.isEmpty,
                  sourceSection == nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Annotation, camera, and light objects must not contain shape component references."
                )
            }
        }
    }
}
