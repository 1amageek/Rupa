import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setSceneNodeObjectProperty(
        id: SceneNodeID,
        propertyID: ObjectPropertyID,
        value: ObjectPropertyValue?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id],
              var object = node.object else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object property changes require an existing object scene node."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            containingGeneratedOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output object properties are controlled by the pattern source."
            )
        }
        guard object.typeID != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Object property changes require a typed object."
            )
        }
        switch object.category {
        case .body, .sketch, .annotation:
            break
        case .group, .componentInstance, .construction, .camera, .light:
            throw EditorError(
                code: .commandInvalid,
                message: "Object properties can only be edited on typed geometry or annotation objects."
            )
        }
        let definition = try objectRegistry.validatePropertyMutation(
            typeID: object.typeID,
            propertyID: propertyID,
            value: value,
            materialLibrary: productMetadata.materialLibrary
        )
        object.properties[propertyID] = value
        try object.properties.validate(
            against: definition,
            materialLibrary: productMetadata.materialLibrary
        )
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[id] = node
        if let property = definition.property(for: propertyID) {
            try applyObjectPropertyToSource(
                sceneNodeID: id,
                object: object,
                definition: definition,
                property: property,
                objectRegistry: objectRegistry
            )
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private mutating func applyObjectPropertyToSource(
        sceneNodeID: SceneNodeID,
        object: ObjectDescriptor,
        definition: ObjectTypeDefinition,
        property: ObjectPropertyDefinition,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let binding = property.renderBinding else {
            return
        }

        switch object.category {
        case .body:
            try applyBodyObjectPropertyToSource(
                object: object,
                definition: definition,
                binding: binding,
                objectRegistry: objectRegistry
            )
        case .sketch:
            guard binding == .extrusion else {
                return
            }
            try applySketchExtrusionPropertyToSource(
                sceneNodeID: sceneNodeID,
                object: object,
                definition: definition,
                objectRegistry: objectRegistry
            )
        case .group, .componentInstance, .construction, .annotation, .camera, .light:
            return
        }
        guard productMetadata.sceneNodes[sceneNodeID] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object property source update lost its scene node."
            )
        }
    }

    private mutating func applyBodyObjectPropertyToSource(
        object: ObjectDescriptor,
        definition: ObjectTypeDefinition,
        binding: ObjectPropertyDefinition.RenderBinding,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let featureID = object.sourceFeatureID else {
            return
        }
        switch object.typeID {
        case .some(.cube):
            guard binding == .sizeX || binding == .sizeY || binding == .sizeZ else {
                return
            }
            let dimensions = try resolvedExtrudedBodyDimensions(featureID: featureID)
            let properties = definition.resolvedProperties(object.properties)
            try setCubeDimensions(
                featureID: featureID,
                sizeX: .length(
                    resolvedLength(
                        for: .sizeX,
                        definition: definition,
                        properties: properties,
                        fallback: dimensions.sizeX
                    ),
                    .meter
                ),
                sizeY: .length(
                    resolvedLength(
                        for: .sizeY,
                        definition: definition,
                        properties: properties,
                        fallback: dimensions.sizeY
                    ),
                    .meter
                ),
                sizeZ: .length(
                    resolvedLength(
                        for: .sizeZ,
                        definition: definition,
                        properties: properties,
                        fallback: dimensions.sizeZ
                    ),
                    .meter
                ),
                objectRegistry: objectRegistry
            )
        case .some(.cylinder):
            guard binding == .sizeX ||
                    binding == .sizeY ||
                    binding == .sizeZ ||
                    binding == .radius else {
                return
            }
            let dimensions = try resolvedExtrudedBodyDimensions(featureID: featureID)
            let properties = definition.resolvedProperties(object.properties)
            let radius: Double
            switch binding {
            case .sizeX:
                radius = resolvedLength(
                    for: .sizeX,
                    definition: definition,
                    properties: properties,
                    fallback: dimensions.sizeX
                ) / 2.0
            case .sizeZ:
                radius = resolvedLength(
                    for: .sizeZ,
                    definition: definition,
                    properties: properties,
                    fallback: dimensions.sizeZ
                ) / 2.0
            case .radius:
                radius = resolvedLength(
                    for: .radius,
                    definition: definition,
                    properties: properties,
                    fallback: dimensions.radius ?? max(dimensions.sizeX, dimensions.sizeZ) / 2.0
                )
            default:
                radius = dimensions.radius ?? max(dimensions.sizeX, dimensions.sizeZ) / 2.0
            }
            try setCylinderDimensions(
                featureID: featureID,
                radius: .length(max(radius, 1.0e-9), .meter),
                sizeY: .length(
                    resolvedLength(
                        for: .sizeY,
                        definition: definition,
                        properties: properties,
                        fallback: dimensions.sizeY
                    ),
                    .meter
                ),
                objectRegistry: objectRegistry
            )
        default:
            return
        }
    }

    private mutating func applySketchExtrusionPropertyToSource(
        sceneNodeID: SceneNodeID,
        object: ObjectDescriptor,
        definition: ObjectTypeDefinition,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let sourceFeatureID = object.sourceFeatureID,
              let extrusionProperty = definition.property(for: .extrusion) else {
            return
        }
        let properties = definition.resolvedProperties(object.properties)
        let value = properties.value(for: extrusionProperty.id, default: extrusionProperty.defaultValue)
        guard case .length(let extrusionMeters) = value else {
            return
        }

        let generatedName = generatedExtrusionBodyName(for: sceneNodeID)
        if extrusionMeters <= 1.0e-9 {
            removeGeneratedExtrusionBody(
                sourceSectionFeatureID: sourceFeatureID,
                generatedName: generatedName
            )
            return
        }

        if let bodyFeatureID = generatedExtrusionBodyFeatureID(
            sourceSectionFeatureID: sourceFeatureID,
            generatedName: generatedName
        ) {
            try setExtrudeDistance(
                featureID: bodyFeatureID,
                distance: .length(extrusionMeters, .meter),
                objectRegistry: objectRegistry
            )
            return
        }

        _ = try extrudeProfile(
            name: generatedName,
            profile: ProfileReference(featureID: sourceFeatureID),
            distance: .length(extrusionMeters, .meter),
            direction: .normal,
            typeID: generatedBodyTypeID(for: object),
            objectRegistry: objectRegistry
        )
    }

    private func generatedExtrusionBodyName(for sceneNodeID: SceneNodeID) -> String {
        let sourceName = productMetadata.sceneNodes[sceneNodeID]?.name ?? "Sketch"
        return "\(sourceName) Extrusion"
    }

    private func generatedBodyTypeID(for object: ObjectDescriptor) -> ObjectTypeID? {
        switch object.typeID {
        case .some(.rectangle):
            return .cube
        case .some(.circle):
            return .cylinder
        default:
            return nil
        }
    }

    private func generatedExtrusionBodyFeatureID(
        sourceSectionFeatureID: FeatureID,
        generatedName: String
    ) -> FeatureID? {
        productMetadata.sceneNodes.values.first { node in
            node.name == generatedName &&
                node.reference?.kind == .body &&
                node.object?.sourceSection?.profileReference?.featureID == sourceSectionFeatureID
        }?.reference?.featureID
    }

    private mutating func removeGeneratedExtrusionBody(
        sourceSectionFeatureID: FeatureID,
        generatedName: String
    ) {
        let generatedNodeIDs = productMetadata.sceneNodes.values.compactMap { node -> SceneNodeID? in
            guard node.name == generatedName,
                  node.reference?.kind == .body,
                  node.object?.sourceSection?.profileReference?.featureID == sourceSectionFeatureID else {
                return nil
            }
            return node.id
        }
        guard !generatedNodeIDs.isEmpty else {
            return
        }
        let generatedNodeIDSet = Set(generatedNodeIDs)
        let generatedFeatureIDs = Set(generatedNodeIDs.compactMap {
            productMetadata.sceneNodes[$0]?.reference?.featureID
        })

        for nodeID in generatedNodeIDs {
            productMetadata.sceneNodes.removeValue(forKey: nodeID)
        }
        productMetadata.rootSceneNodeIDs.removeAll { generatedNodeIDSet.contains($0) }
        for nodeID in productMetadata.sceneNodes.keys {
            productMetadata.sceneNodes[nodeID]?.childIDs.removeAll { generatedNodeIDSet.contains($0) }
        }

        guard !generatedFeatureIDs.isEmpty else {
            return
        }
        cadDocument.designGraph.order.removeAll { generatedFeatureIDs.contains($0) }
        for featureID in generatedFeatureIDs {
            cadDocument.designGraph.nodes.removeValue(forKey: featureID)
        }
        cadDocument.designGraph.dependencies.removeAll {
            generatedFeatureIDs.contains($0.source) || generatedFeatureIDs.contains($0.target)
        }
        cadDocument.designGraph.revision = cadDocument.designGraph.revision.advanced()
    }

    mutating func synchronizeObjectPropertiesFromSource(
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let dimensions = try resolvedExtrudedBodyDimensions(featureID: featureID)
        if dimensions.radius != nil {
            try synchronizeCylinderObjectProperties(
                featureID: featureID,
                radius: dimensions.radius ?? max(dimensions.sizeX, dimensions.sizeZ) / 2.0,
                sizeY: dimensions.sizeY,
                objectRegistry: objectRegistry
            )
        } else {
            try synchronizeBodyObjectSizeProperties(
                featureID: featureID,
                sizeX: dimensions.sizeX,
                sizeY: dimensions.sizeY,
                sizeZ: dimensions.sizeZ,
                objectRegistry: objectRegistry
            )
        }
    }

    mutating func synchronizeObjectPropertiesAffectedBySketch(
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        for bodyFeatureID in cadDocument.designGraph.order {
            guard let feature = cadDocument.designGraph.nodes[bodyFeatureID],
                  case let .extrude(extrude) = feature.operation,
                  extrude.profile.featureID == featureID else {
                continue
            }
            try synchronizeObjectPropertiesFromSource(
                featureID: bodyFeatureID,
                objectRegistry: objectRegistry
            )
        }
    }

    mutating func synchronizeBodyObjectSizeProperties(
        featureID: FeatureID,
        sizeX: Double,
        sizeY: Double,
        sizeZ: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        try updateBodyObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
            Self.setLengthProperty(.sizeX, to: sizeX, object: &object, definition: definition)
            Self.setLengthProperty(.sizeY, to: sizeY, object: &object, definition: definition)
            Self.setLengthProperty(.sizeZ, to: sizeZ, object: &object, definition: definition)
        }
    }

    mutating func synchronizeCylinderObjectProperties(
        featureID: FeatureID,
        radius: Double,
        sizeY: Double,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        try updateBodyObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
            Self.setLengthProperty(.radius, to: radius, object: &object, definition: definition)
            Self.setLengthProperty(.sizeX, to: radius * 2.0, object: &object, definition: definition)
            Self.setLengthProperty(.sizeY, to: sizeY, object: &object, definition: definition)
            Self.setLengthProperty(.sizeZ, to: radius * 2.0, object: &object, definition: definition)
        }
    }

    private mutating func updateBodyObjectProperties(
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry,
        update: (inout ObjectDescriptor, ObjectTypeDefinition) -> Void
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .body,
            object.typeID != nil else {
            return
        }
        let definition = try objectRegistry.requireDefinition(for: object.typeID)
        var resolved = definition.resolvedProperties(object.properties)
        object.properties = resolved
        update(&object, definition)
        resolved = definition.resolvedProperties(object.properties)
        try resolved.validate(
            against: definition,
            materialLibrary: productMetadata.materialLibrary
        )
        object.properties = resolved
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    mutating func markBodyObjectAsSourceEditedSolid(
        featureID: FeatureID,
        profileArcSegmentCount: Int? = nil
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .body else {
            return
        }
        let resolvedArcSegmentCount = profileArcSegmentCount
            ?? ProfileTessellationPolicy.arcSegmentCount(from: object)
        object.geometryRole = .solid
        object.typeID = nil
        object.properties = ObjectPropertySet()
        if let resolvedArcSegmentCount {
            object.properties[ProfileTessellationPolicy.arcSegmentsPropertyID] = .integer(
                ProfileTessellationPolicy.clampedArcSegmentCount(resolvedArcSegmentCount)
            )
        }
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    static func setLengthProperty(
        _ binding: ObjectPropertyDefinition.RenderBinding,
        to meters: Double,
        object: inout ObjectDescriptor,
        definition: ObjectTypeDefinition
    ) {
        guard let property = definition.property(for: binding),
              property.valueKind == .length else {
            return
        }
        object.properties[property.id] = .length(meters)
    }

    static func setLengthProperty(
        _ id: ObjectPropertyID,
        to meters: Double,
        object: inout ObjectDescriptor,
        definition: ObjectTypeDefinition
    ) {
        guard let property = definition.property(for: id),
              property.valueKind == .length else {
            return
        }
        object.properties[property.id] = .length(meters)
    }

    static func setAngleProperty(
        _ id: ObjectPropertyID,
        to degrees: Double,
        object: inout ObjectDescriptor,
        definition: ObjectTypeDefinition
    ) {
        guard let property = definition.property(for: id),
              property.valueKind == .angle else {
            return
        }
        object.properties[property.id] = .angle(normalizedAngleDegrees(degrees))
    }

    static func setIntegerProperty(
        _ id: ObjectPropertyID,
        to value: Int,
        object: inout ObjectDescriptor,
        definition: ObjectTypeDefinition
    ) {
        guard let property = definition.property(for: id),
              property.valueKind == .integer else {
            return
        }
        object.properties[property.id] = .integer(value)
    }

    static func normalizedAngleDegrees(_ degrees: Double) -> Double {
        var normalized = degrees.truncatingRemainder(dividingBy: 360.0)
        if normalized < 0.0 {
            normalized += 360.0
        }
        normalized = CADInputValueNormalizer.standard.angleDegrees(normalized)
        return normalized == -0.0 ? 0.0 : normalized
    }

    private func resolvedLength(
        for binding: ObjectPropertyDefinition.RenderBinding,
        definition: ObjectTypeDefinition,
        properties: ObjectPropertySet,
        fallback: Double
    ) -> Double {
        guard let property = definition.property(for: binding) else {
            return fallback
        }
        let value = properties.value(for: property.id, default: property.defaultValue)
        guard case .length(let meters) = value,
              meters.isFinite else {
            return fallback
        }
        return max(meters, 1.0e-9)
    }
}
