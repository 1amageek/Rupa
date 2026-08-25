import Foundation
import SwiftCAD
import RupaProjectModel

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
    public var geometryRepresentations: GeometryRepresentationSet
    public var sourceSection: BodySourceSectionReference?
    public var componentInstanceID: ComponentInstanceID?

    public var sourceFeatureID: FeatureID? {
        guard case let .cad(_, outputID)? = geometryRepresentations.source(for: .modeling),
              let uuid = UUID(uuidString: outputID) else {
            return nil
        }
        return FeatureID(uuid)
    }

    public init(
        category: Category,
        geometryRole: GeometryRole? = nil,
        typeID: ObjectTypeID? = nil,
        properties: ObjectPropertySet = ObjectPropertySet(),
        geometryRepresentations: GeometryRepresentationSet = .empty,
        sourceSection: BodySourceSectionReference? = nil,
        componentInstanceID: ComponentInstanceID? = nil
    ) {
        self.category = category
        self.geometryRole = geometryRole
        self.typeID = typeID
        self.properties = properties
        self.geometryRepresentations = geometryRepresentations
        self.sourceSection = sourceSection
        self.componentInstanceID = componentInstanceID
    }

    public static func group() -> ObjectDescriptor {
        ObjectDescriptor(category: .group)
    }

    public static func sketch(
        featureID: FeatureID,
        documentID: DocumentID,
        typeID: ObjectTypeID? = nil,
        geometryRole: GeometryRole = .sketchProfile,
        properties: ObjectPropertySet = ObjectPropertySet(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> ObjectDescriptor {
        let defaultProperties = objectRegistry.defaultProperties(for: typeID)
        let resolvedProperties = defaultProperties.merging(properties)
        return ObjectDescriptor(
            category: .sketch,
            geometryRole: objectRegistry.geometryRole(for: typeID) ?? geometryRole,
            typeID: typeID,
            properties: resolvedProperties,
            geometryRepresentations: cadRepresentations(
                documentID: documentID,
                featureID: featureID
            )
        )
    }

    public static func body(
        featureID: FeatureID,
        documentID: DocumentID,
        sourceSection: BodySourceSectionReference?,
        typeID: ObjectTypeID?,
        geometryRole: GeometryRole = .solid,
        properties: ObjectPropertySet = ObjectPropertySet(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) -> ObjectDescriptor {
        let defaultProperties = objectRegistry.defaultProperties(for: typeID)
        let resolvedProperties = defaultProperties.merging(properties)
        return ObjectDescriptor(
            category: .body,
            geometryRole: objectRegistry.geometryRole(for: typeID) ?? geometryRole,
            typeID: typeID,
            properties: resolvedProperties,
            geometryRepresentations: cadRepresentations(
                documentID: documentID,
                featureID: featureID
            ),
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
                  geometryRepresentations == .empty,
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
                  geometryRepresentations == .empty,
                  sourceSection == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instance objects must contain exactly one component instance reference."
                )
            }
        case .body:
            guard geometryRole != nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Body objects must contain a geometry role without a component instance reference."
                )
            }
            try validateGeometryRepresentations(requiresSelection: true)
            try properties.validate()
        case .sketch:
            guard geometryRole == .sketchProfile || geometryRole == .curve,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Sketch objects must contain one sketch profile or curve role."
                )
            }
            try validateGeometryRepresentations(requiresSelection: true)
            try properties.validate()
        case .construction:
            guard geometryRole == .construction,
                  typeID == nil,
                  properties.values.isEmpty,
                  geometryRepresentations == .empty,
                  sourceSection == nil,
                  componentInstanceID == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction objects must not contain feature or component references."
                )
            }
        case .annotation:
            guard componentInstanceID == nil,
                  sourceSection == nil,
                  geometryRepresentations == .empty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Annotation objects must not contain profile or component references."
                )
            }
            try properties.validate()
        case .camera, .light:
            guard typeID == nil,
                  properties.values.isEmpty,
                  sourceSection == nil,
                  componentInstanceID == nil,
                  geometryRepresentations == .empty else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Annotation, camera, and light objects must not contain shape component references."
                )
            }
        }
    }

    mutating func remapCADRepresentations(
        using featureIDMap: [FeatureID: FeatureID]
    ) throws {
        var remappedRepresentations: [GeometryRepresentationID: GeometryRepresentation] = [:]
        var representationIDMap: [GeometryRepresentationID: GeometryRepresentationID] = [:]
        for representation in geometryRepresentations.representations.values {
            let remappedRepresentation: GeometryRepresentation
            if case let .cad(sourceID, outputID) = representation.source,
               let uuid = UUID(uuidString: outputID),
               let remappedFeatureID = featureIDMap[FeatureID(uuid)] {
                let remappedID = Self.cadRepresentationID(featureID: remappedFeatureID)
                remappedRepresentation = GeometryRepresentation(
                    id: remappedID,
                    source: .cad(
                        sourceID: sourceID,
                        outputID: remappedFeatureID.description
                    )
                )
                representationIDMap[representation.id] = remappedID
            } else {
                remappedRepresentation = representation
            }
            guard remappedRepresentations[remappedRepresentation.id] == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Independent-copy CAD representation remapping produced a duplicate representation ID."
                )
            }
            remappedRepresentations[remappedRepresentation.id] = remappedRepresentation
        }
        geometryRepresentations.representations = remappedRepresentations
        if var selection = geometryRepresentations.selection {
            selection.modeling = representationIDMap[selection.modeling] ?? selection.modeling
            selection.presentation = representationIDMap[selection.presentation] ?? selection.presentation
            geometryRepresentations.selection = selection
        }
    }

    private func validateGeometryRepresentations(
        requiresSelection: Bool
    ) throws {
        do {
            try geometryRepresentations.validate(requiresSelection: requiresSelection)
        } catch let error as ProjectModelError {
            throw DocumentValidationError.invalidProductMetadata(error.message)
        }
    }

    private static func cadRepresentations(
        documentID: DocumentID,
        featureID: FeatureID
    ) -> GeometryRepresentationSet {
        let representationID = cadRepresentationID(featureID: featureID)
        return GeometryRepresentationSet(
            representations: [
                representationID: GeometryRepresentation(
                    id: representationID,
                    source: .cad(
                        sourceID: documentID.description,
                        outputID: featureID.description
                    )
                ),
            ],
            selection: GeometryRepresentationSelection(
                modeling: representationID,
                presentation: representationID
            )
        )
    }

    private static func cadRepresentationID(
        featureID: FeatureID
    ) -> GeometryRepresentationID {
        GeometryRepresentationID(rawValue: "cad.\(featureID.description)")
    }
}
