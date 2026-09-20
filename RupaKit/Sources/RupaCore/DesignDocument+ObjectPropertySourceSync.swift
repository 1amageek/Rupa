import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setSceneNodeObjectProperty(
        id: SceneNodeID,
        propertyID: PropertyID,
        value: ObjectPropertyValue?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        var updated = self
        try updated.applySceneNodeObjectProperty(id: id, propertyID: propertyID, value: value,
                                               objectRegistry: objectRegistry)
        self = updated
    }

    private mutating func applySceneNodeObjectProperty(
        id: SceneNodeID, propertyID: PropertyID, value: ObjectPropertyValue?,
        objectRegistry: ObjectTypeRegistry
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
        switch property.effect {
        case .tessellation, .appearance, .derived:
            // These effects change display resolution or presentation, not the feature graph.
            return
        case .source:
            break
        }

        switch object.category {
        case .body:
            guard let binding = property.renderBinding else {
                throw unsupportedObjectSourceProperty(property, definition: definition)
            }
            try applyBodyObjectPropertyToSource(
                object: object,
                definition: definition,
                binding: binding,
                objectRegistry: objectRegistry
            )
        case .sketch:
            try applySketchObjectPropertyToSource(
                sceneNodeID: sceneNodeID,
                object: object,
                definition: definition,
                property: property,
                objectRegistry: objectRegistry
            )
        case .group, .componentInstance, .construction, .annotation, .camera, .light:
            throw unsupportedObjectSourceProperty(property, definition: definition)
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
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object property source updates require a body built by a feature."
            )
        }
        switch object.typeID {
        case .some(.cube):
            if binding == .cornerRadius {
                guard let property = definition.properties.first(where: { $0.renderBinding == binding }),
                      case .length(let radius) = definition.resolvedProperties(object.properties)[property.id] else {
                    throw EditorError(code: .commandInvalid, message: "Corner requires a length value.")
                }
                try setBoxCorner(featureID: featureID, radius: radius)
                return
            }
            guard binding == .sizeX || binding == .sizeY || binding == .sizeZ else {
                throw unsupportedObjectSourceProperty(
                    binding: binding,
                    definition: definition
                )
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
                throw unsupportedObjectSourceProperty(
                    binding: binding,
                    definition: definition
                )
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
            throw unsupportedObjectSourceProperty(
                binding: binding,
                definition: definition
            )
        }
    }

    /// Routes a sketch object's `source` property to the mutator that owns its shape.
    ///
    /// Dispatch is on the object's declared type and property ID rather than the render binding,
    /// because several types bind the same slot to different profile geometry. Every mutator
    /// rebuilds the profile from the whole resolved property set, so an edit to one property keeps
    /// the others the document already authored.
    private mutating func applySketchObjectPropertyToSource(
        sceneNodeID: SceneNodeID,
        object: ObjectDescriptor,
        definition: ObjectTypeDefinition,
        property: ObjectPropertyDefinition,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        if property.renderBinding == .extrusion {
            try applySketchExtrusionPropertyToSource(
                sceneNodeID: sceneNodeID,
                object: object,
                definition: definition,
                objectRegistry: objectRegistry
            )
            return
        }
        guard let featureID = object.sourceFeatureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Shape changes require a sketch built by a feature."
            )
        }
        let properties = definition.resolvedProperties(object.properties)

        switch object.typeID {
        case .some(.line):
            guard property.id == "length" || property.id == "angle" else {
                throw unsupportedObjectSourceProperty(property, definition: definition)
            }
            try setLineSketchGeometry(
                featureID: featureID,
                lengthMeters: try requiredLengthMeters(
                    "length",
                    definition: definition,
                    properties: properties
                ),
                angleDegrees: try requiredAngleDegrees(
                    "angle",
                    definition: definition,
                    properties: properties
                ),
                objectRegistry: objectRegistry
            )
        case .some(.arc):
            guard property.id == "radius"
                    || property.id == "start.angle"
                    || property.id == "end.angle" else {
                throw unsupportedObjectSourceProperty(property, definition: definition)
            }
            try setArcSketchGeometry(
                featureID: featureID,
                radiusMeters: try requiredLengthMeters(
                    "radius",
                    definition: definition,
                    properties: properties
                ),
                startAngleDegrees: try requiredAngleDegrees(
                    "start.angle",
                    definition: definition,
                    properties: properties
                ),
                endAngleDegrees: try requiredAngleDegrees(
                    "end.angle",
                    definition: definition,
                    properties: properties
                ),
                objectRegistry: objectRegistry
            )
        case .some(.circle):
            guard property.id == "radius" else {
                throw unsupportedObjectSourceProperty(property, definition: definition)
            }
            try setCircleSketchGeometry(
                featureID: featureID,
                radiusMeters: try requiredLengthMeters(
                    "radius",
                    definition: definition,
                    properties: properties
                ),
                objectRegistry: objectRegistry
            )
        case .some(.rectangle):
            guard property.id == "size.x" || property.id == "size.y" else {
                throw unsupportedObjectSourceProperty(property, definition: definition)
            }
            // A rounded rectangle is a different profile, not a resized one. Rebuilding it here
            // would silently square off the corners the document authored.
            let cornerRadius = try requiredLengthMeters(
                "corner.radius",
                definition: definition,
                properties: properties
            )
            guard cornerRadius <= 1.0e-9 else {
                throw unsupportedObjectSourceProperty(
                    definition.property(for: PropertyID(rawValue: "corner.radius")) ?? property,
                    definition: definition
                )
            }
            try setRectangleSketchGeometry(
                featureID: featureID,
                sizeXMeters: try requiredLengthMeters(
                    "size.x",
                    definition: definition,
                    properties: properties
                ),
                sizeYMeters: try requiredLengthMeters(
                    "size.y",
                    definition: definition,
                    properties: properties
                ),
                objectRegistry: objectRegistry
            )
        case .some(.polygon):
            guard property.id == "sizing.radius"
                    || property.id == "radius.is.inradius"
                    || property.id == "sides.x"
                    || property.id == "angle" else {
                throw unsupportedObjectSourceProperty(property, definition: definition)
            }
            try setPolygonSketchGeometry(
                featureID: featureID,
                sizingRadiusMeters: try requiredLengthMeters(
                    "sizing.radius",
                    definition: definition,
                    properties: properties
                ),
                isInradius: try requiredBoolean(
                    "radius.is.inradius",
                    definition: definition,
                    properties: properties
                ),
                sides: try requiredInteger(
                    "sides.x",
                    definition: definition,
                    properties: properties
                ),
                rotationDegrees: try requiredAngleDegrees(
                    "angle",
                    definition: definition,
                    properties: properties
                ),
                objectRegistry: objectRegistry
            )
        default:
            throw unsupportedObjectSourceProperty(property, definition: definition)
        }
    }

    private func requiredPropertyValue(
        _ id: PropertyID,
        definition: ObjectTypeDefinition,
        properties: ObjectPropertySet
    ) throws -> ObjectPropertyValue {
        guard let property = definition.property(for: id) else {
            throw EditorError(
                code: .commandUnsupported,
                message: "\(definition.title) does not declare a \(id.rawValue) property."
            )
        }
        return properties.value(for: property.id, default: property.defaultValue)
    }

    private func requiredLengthMeters(
        _ id: PropertyID,
        definition: ObjectTypeDefinition,
        properties: ObjectPropertySet
    ) throws -> Double {
        guard case let .length(meters) = try requiredPropertyValue(
            id,
            definition: definition,
            properties: properties
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(definition.title) \(id.rawValue) requires a length value."
            )
        }
        return meters
    }

    private func requiredAngleDegrees(
        _ id: PropertyID,
        definition: ObjectTypeDefinition,
        properties: ObjectPropertySet
    ) throws -> Double {
        guard case let .angle(degrees) = try requiredPropertyValue(
            id,
            definition: definition,
            properties: properties
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(definition.title) \(id.rawValue) requires an angle value."
            )
        }
        return degrees
    }

    private func requiredInteger(
        _ id: PropertyID,
        definition: ObjectTypeDefinition,
        properties: ObjectPropertySet
    ) throws -> Int {
        guard case let .integer(value) = try requiredPropertyValue(
            id,
            definition: definition,
            properties: properties
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(definition.title) \(id.rawValue) requires an integer value."
            )
        }
        return value
    }

    private func requiredBoolean(
        _ id: PropertyID,
        definition: ObjectTypeDefinition,
        properties: ObjectPropertySet
    ) throws -> Bool {
        guard case let .boolean(value) = try requiredPropertyValue(
            id,
            definition: definition,
            properties: properties
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(definition.title) \(id.rawValue) requires a boolean value."
            )
        }
        return value
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Several schema properties declare the `source` effect but
    // have no router branch yet, so every edit to one fails here instead of reaching the canvas.
    // Production path: the Inspector shape section submits `setSceneNodeObjectProperty`, which
    // routes through `applyObjectPropertyToSource`. Unrouted today: rectangle `corner.radius`; the
    // `bevel` property on every extruded profile; and cylinder `angle`, `caps`, `hollow`,
    // `corner.radius`. Do not treat an edit to any of these as applied until its branch exists and
    // a test drives the property through to the evaluated geometry.
    private func unsupportedObjectSourceProperty(
        binding: ObjectPropertyDefinition.RenderBinding,
        definition: ObjectTypeDefinition
    ) -> EditorError {
        guard let property = definition.properties.first(where: { $0.renderBinding == binding }) else {
            return EditorError(
                code: .commandUnsupported,
                message: "\(definition.title) does not apply \(binding.rawValue) to its source geometry."
            )
        }
        return unsupportedObjectSourceProperty(property, definition: definition)
    }

    private func unsupportedObjectSourceProperty(
        _ property: ObjectPropertyDefinition,
        definition: ObjectTypeDefinition
    ) -> EditorError {
        EditorError(
            code: .commandUnsupported,
            message: "\(definition.title) does not apply \(property.title) to its source geometry."
        )
    }

    private mutating func applySketchExtrusionPropertyToSource(
        sceneNodeID: SceneNodeID,
        object: ObjectDescriptor,
        definition: ObjectTypeDefinition,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let sourceFeatureID = object.sourceFeatureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrusion changes require a sketch built by a feature."
            )
        }
        guard let extrusionProperty = definition.property(for: .extrusion) else {
            throw EditorError(
                code: .commandUnsupported,
                message: "\(definition.title) does not declare an extrusion property."
            )
        }
        let properties = definition.resolvedProperties(object.properties)
        let value = properties.value(for: extrusionProperty.id, default: extrusionProperty.defaultValue)
        guard case .length(let extrusionMeters) = value else {
            throw EditorError(code: .commandInvalid, message: "Extrusion requires a length value.")
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
        _ id: PropertyID,
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
        _ id: PropertyID,
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
        _ id: PropertyID,
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
