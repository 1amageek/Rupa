import Foundation
import SwiftCAD

public struct DesignDocument: Identifiable, Sendable {
    public var cadDocument: CADDocument
    public var displayUnit: LengthDisplayUnit
    public var ruler: RulerConfiguration
    public var productMetadata: ProductMetadata

    public var id: DocumentID {
        cadDocument.id
    }

    public init(
        cadDocument: CADDocument,
        displayUnit: LengthDisplayUnit,
        ruler: RulerConfiguration,
        productMetadata: ProductMetadata = .empty()
    ) {
        self.cadDocument = cadDocument
        self.displayUnit = displayUnit
        self.ruler = ruler
        self.productMetadata = productMetadata
    }

    public static func empty(named name: String = "Untitled") -> DesignDocument {
        let unit: LengthDisplayUnit = .millimeter
        return DesignDocument(
            cadDocument: CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: name)
            ),
            displayUnit: unit,
            ruler: .standard(for: unit),
            productMetadata: .empty()
        )
    }

    public mutating func setDisplayUnit(_ unit: LengthDisplayUnit) {
        displayUnit = unit
        ruler = .standard(for: unit)
    }

    public mutating func setRulerConfiguration(_ configuration: RulerConfiguration) throws {
        try configuration.validate()
        displayUnit = configuration.displayUnit
        ruler = configuration
    }

    public mutating func rename(_ name: String, updatedAt: Date = Date()) {
        cadDocument.metadata.name = name
        cadDocument.metadata.updatedAt = updatedAt
    }

    public mutating func upsertParameter(
        name: String,
        expression: CADExpression,
        kind: QuantityKind
    ) {
        let existingID = cadDocument.parameters.parameters.values
            .first { $0.name == name }?
            .id ?? ParameterID()
        cadDocument.parameters.parameters[existingID] = Parameter(
            id: existingID,
            name: name,
            expression: expression,
            kind: kind
        )
        cadDocument.parameters.revision = cadDocument.parameters.revision.advanced()
    }

    public mutating func deleteParameter(name: String) throws {
        guard let parameterID = cadDocument.parameters.parameters.values
            .first(where: { $0.name == name })?
            .id else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Parameter delete requires an existing parameter."
            )
        }

        var updatedCADDocument = cadDocument
        updatedCADDocument.parameters.parameters.removeValue(forKey: parameterID)
        updatedCADDocument.parameters.revision = updatedCADDocument.parameters.revision.advanced()
        do {
            try updatedCADDocument.validate()
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Parameter \(name) is still referenced: \(error)."
            )
        }
        cadDocument = updatedCADDocument
    }

    @discardableResult
    public mutating func createComponentDefinition(
        name: String,
        rootSceneNodeIDs: [SceneNodeID] = [],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ComponentDefinitionID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Component definition"
        )
        guard productMetadata.componentDefinitions.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Component definition names must be unique."
            )
        }
        for rootSceneNodeID in rootSceneNodeIDs {
            guard productMetadata.sceneNodes[rootSceneNodeID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Component definition root scene nodes must exist."
                )
            }
        }

        let definition = ComponentDefinition(
            name: trimmedName,
            rootSceneNodeIDs: rootSceneNodeIDs
        )
        productMetadata.componentDefinitions[definition.id] = definition
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return definition.id
    }

    @discardableResult
    public mutating func createComponentInstance(
        name: String,
        definitionID: ComponentDefinitionID,
        localTransform: Transform3D = .identity,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ComponentInstanceID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Component instance"
        )
        guard productMetadata.componentDefinitions[definitionID] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instances must reference an existing component definition."
            )
        }
        guard productMetadata.componentInstances.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Component instance names must be unique."
            )
        }

        let instance = ComponentInstance(
            definitionID: definitionID,
            name: trimmedName,
            localTransform: localTransform
        )
        productMetadata.componentInstances[instance.id] = instance
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .componentInstance(instance.id),
            object: .componentInstance(instance.id)
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return instance.id
    }

    public mutating func setSceneNodeVisibility(
        id: SceneNodeID,
        isVisible: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node visibility requires an existing scene node."
            )
        }
        node.isVisible = isVisible
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSceneNodeLock(
        id: SceneNodeID,
        isLocked: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node lock requires an existing scene node."
            )
        }
        node.isLocked = isLocked
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSceneNodeTransform(
        id: SceneNodeID,
        localTransform: Transform3D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node transform requires an existing scene node."
            )
        }
        try localTransform.validate()
        node.localTransform = localTransform
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setSceneNodeMaterial(
        id: SceneNodeID,
        materialID: MaterialID?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node material requires an existing scene node."
            )
        }
        if let materialID,
           productMetadata.materialLibrary.materials[materialID] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node material requires an existing material."
            )
        }
        node.materialID = materialID
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

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

    public mutating func setComponentInstanceVisibility(
        id: ComponentInstanceID,
        isVisible: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instance visibility requires an existing component instance."
            )
        }
        instance.isVisible = isVisible
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setComponentInstanceLock(
        id: ComponentInstanceID,
        isLocked: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instance lock requires an existing component instance."
            )
        }
        instance.isLocked = isLocked
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setComponentInstanceTransform(
        id: ComponentInstanceID,
        localTransform: Transform3D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Component instance transform requires an existing component instance."
            )
        }
        try localTransform.validate()
        instance.localTransform = localTransform
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func createSectionPlane(
        name: String,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SceneNodeID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Section plane"
        )
        let sceneNodeID = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .construction,
            object: .construction()
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return sceneNodeID
    }

    @discardableResult
    public mutating func createLineSketch(
        name: String,
        plane: SketchPlane,
        start: SketchPoint,
        end: SketchPoint,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let startX = try resolvedLengthValue(start.x, owner: "Line start x")
        let startY = try resolvedLengthValue(start.y, owner: "Line start y")
        let endX = try resolvedLengthValue(end.x, owner: "Line end x")
        let endY = try resolvedLengthValue(end.y, owner: "Line end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Line sketch length must be greater than zero."
            )
        }
        var builder = SketchBuilder(on: plane)
        _ = builder.line(from: start, to: end)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .line,
            geometryRole: .curve,
            properties: ObjectPropertySet(values: [
                "length": .length(length),
                "angle": .angle(atan2(deltaY, deltaX) * 180.0 / .pi),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createCircleSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedRadius = try resolvedLengthValue(radius, owner: "Circle radius")
        guard resolvedRadius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Circle sketch radius must be greater than zero."
            )
        }

        var builder = SketchBuilder(on: plane)
        builder.circle(center: center, radius: radius)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .circle,
            properties: ObjectPropertySet(values: [
                "radius": .length(resolvedRadius),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createRectangleSketch(
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedWidth = try resolvedLengthValue(width, owner: "Rectangle width")
        let resolvedHeight = try resolvedLengthValue(height, owner: "Rectangle height")
        guard resolvedWidth > 0.0, resolvedHeight > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Rectangle sketch size must be greater than zero."
            )
        }
        var builder = SketchBuilder(on: plane)
        builder.rectangle(width: width, height: height)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .rectangle,
            properties: ObjectPropertySet(values: [
                "size.x": .length(resolvedWidth),
                "size.y": .length(resolvedHeight),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createRectangleSketchFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let firstX = try resolvedLengthValue(firstCorner.x, owner: "Rectangle first corner x")
        let firstY = try resolvedLengthValue(firstCorner.y, owner: "Rectangle first corner y")
        let oppositeX = try resolvedLengthValue(oppositeCorner.x, owner: "Rectangle opposite corner x")
        let oppositeY = try resolvedLengthValue(oppositeCorner.y, owner: "Rectangle opposite corner y")
        guard firstX != oppositeX, firstY != oppositeY else {
            throw EditorError(
                code: .commandInvalid,
                message: "Rectangle sketch corners must define a non-zero width and height."
            )
        }

        let bottom = SketchEntityID()
        let right = SketchEntityID()
        let top = SketchEntityID()
        let left = SketchEntityID()
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        let sketch = Sketch(
            plane: plane,
            entities: [
                bottom: .line(SketchLine(start: bottomLeft, end: bottomRight)),
                right: .line(SketchLine(start: bottomRight, end: topRight)),
                top: .line(SketchLine(start: topRight, end: topLeft)),
                left: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ],
            constraints: [
                .horizontal(bottom),
                .vertical(right),
                .horizontal(top),
                .vertical(left),
                .coincident(.lineEnd(bottom), .lineStart(right)),
                .coincident(.lineEnd(right), .lineStart(top)),
                .coincident(.lineEnd(top), .lineStart(left)),
                .coincident(.lineEnd(left), .lineStart(bottom)),
            ]
        )
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .rectangle,
            properties: ObjectPropertySet(values: [
                "size.x": .length(abs(oppositeX - firstX)),
                "size.y": .length(abs(oppositeY - firstY)),
            ]),
            objectRegistry: objectRegistry
        )
    }

    public mutating func addSketchConstraint(
        featureID: FeatureID,
        constraint: SketchConstraint,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint requires an existing sketch feature."
            )
        }
        guard case var .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint requires a sketch feature."
            )
        }
        guard !sketch.constraints.contains(constraint) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch constraint already exists."
            )
        }

        sketch.constraints.append(constraint)
        feature.operation = .sketch(sketch)

        var updatedCADDocument = cadDocument
        updatedCADDocument.designGraph.nodes[featureID] = feature
        updatedCADDocument.designGraph.revision = updatedCADDocument.designGraph.revision.advanced()
        do {
            try updatedCADDocument.validate()
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint references invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setExtrudeDistance(
        featureID: FeatureID,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        _ = try resolvedLengthValue(distance, owner: "Extrude distance")
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude distance requires an existing feature."
            )
        }
        guard case var .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude distance requires an extrude feature."
            )
        }

        extrude.distance = distance
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        updatedCADDocument.designGraph.nodes[featureID] = feature
        updatedCADDocument.designGraph.revision = updatedCADDocument.designGraph.revision.advanced()
        do {
            try updatedCADDocument.validate()
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude distance produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setCubeDimensions(
        featureID: FeatureID,
        sizeX: CADExpression,
        sizeY: CADExpression,
        sizeZ: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let sizeXMeters = try resolvedPositiveLengthValue(sizeX, owner: "Cube size X")
        let sizeZMeters = try resolvedPositiveLengthValue(sizeZ, owner: "Cube size Z")
        let sizeYMeters = try resolvedPositiveLengthValue(sizeY, owner: "Cube size Y")
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an existing body feature."
            )
        }
        guard case var .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an extrude feature."
            )
        }
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an editable rectangle profile."
            )
        }
        guard isRectangleProfile(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require a rectangle profile."
            )
        }
        guard let bounds = try resolvedSketchBounds2D(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require a rectangle profile with finite bounds."
            )
        }

        let centerX = (bounds.minX + bounds.maxX) / 2.0
        let centerY = (bounds.minY + bounds.maxY) / 2.0
        let firstCorner = SketchPoint(
            x: .length(centerX - sizeXMeters / 2.0, .meter),
            y: .length(centerY - sizeZMeters / 2.0, .meter)
        )
        let oppositeCorner = SketchPoint(
            x: .length(centerX + sizeXMeters / 2.0, .meter),
            y: .length(centerY + sizeZMeters / 2.0, .meter)
        )

        var updatedSketch = sketch
        try updateRectangleSketch(
            &updatedSketch,
            firstCorner: firstCorner,
            oppositeCorner: oppositeCorner
        )
        profileFeature.operation = .sketch(updatedSketch)
        extrude.distance = sizeY
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        updatedCADDocument.designGraph.nodes[extrude.profile.featureID] = profileFeature
        updatedCADDocument.designGraph.nodes[featureID] = feature
        updatedCADDocument.designGraph.revision = updatedCADDocument.designGraph.revision.advanced()
        do {
            try updatedCADDocument.validate()
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeBodyObjectSizeProperties(
            featureID: featureID,
            sizeX: sizeXMeters,
            sizeY: sizeYMeters,
            sizeZ: sizeZMeters,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setCylinderDimensions(
        featureID: FeatureID,
        radius: CADExpression,
        sizeY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let radiusMeters = try resolvedPositiveLengthValue(radius, owner: "Cylinder radius")
        let sizeYMeters = try resolvedPositiveLengthValue(sizeY, owner: "Cylinder size Y")
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cylinder dimensions require an existing body feature."
            )
        }
        guard case var .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cylinder dimensions require an extrude feature."
            )
        }
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case var .sketch(sketch) = profileFeature.operation,
              let circleEntry = singleCircleEntry(in: sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cylinder dimensions require an editable circle profile."
            )
        }

        sketch.entities[circleEntry.id] = .circle(
            SketchCircle(
                center: circleEntry.circle.center,
                radius: radius
            )
        )
        profileFeature.operation = .sketch(sketch)
        extrude.distance = sizeY
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        updatedCADDocument.designGraph.nodes[extrude.profile.featureID] = profileFeature
        updatedCADDocument.designGraph.nodes[featureID] = feature
        updatedCADDocument.designGraph.revision = updatedCADDocument.designGraph.revision.advanced()
        do {
            try updatedCADDocument.validate()
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cylinder dimensions produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeCylinderObjectProperties(
            featureID: featureID,
            radius: radiusMeters,
            sizeY: sizeYMeters,
            objectRegistry: objectRegistry
        )
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
                sourceProfileFeatureID: sourceFeatureID,
                generatedName: generatedName
            )
            return
        }

        if let bodyFeatureID = generatedExtrusionBodyFeatureID(
            sourceProfileFeatureID: sourceFeatureID,
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
        sourceProfileFeatureID: FeatureID,
        generatedName: String
    ) -> FeatureID? {
        productMetadata.sceneNodes.values.first { node in
            node.name == generatedName &&
                node.reference?.kind == .body &&
                node.object?.sourceProfileFeatureID == sourceProfileFeatureID
        }?.reference?.featureID
    }

    private mutating func removeGeneratedExtrusionBody(
        sourceProfileFeatureID: FeatureID,
        generatedName: String
    ) {
        let generatedNodeIDs = productMetadata.sceneNodes.values.compactMap { node -> SceneNodeID? in
            guard node.name == generatedName,
                  node.reference?.kind == .body,
                  node.object?.sourceProfileFeatureID == sourceProfileFeatureID else {
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

    private mutating func synchronizeObjectPropertiesFromSource(
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

    private mutating func synchronizeObjectPropertiesAffectedBySketch(
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

    private mutating func synchronizeBodyObjectSizeProperties(
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

    private mutating func synchronizeCylinderObjectProperties(
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

    private static func setLengthProperty(
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

    private func resolvedExtrudedBodyDimensions(
        featureID: FeatureID
    ) throws -> (sizeX: Double, sizeY: Double, sizeZ: Double, radius: Double?) {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation,
              let profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimensions require an extruded sketch body."
            )
        }
        let depth = try resolvedLengthValue(extrude.distance, owner: "Extrude distance")
        if let circleEntry = singleCircleEntry(in: sketch) {
            let radius = try resolvedPositiveLengthValue(circleEntry.circle.radius, owner: "Cylinder radius")
            return (
                sizeX: radius * 2.0,
                sizeY: abs(depth),
                sizeZ: radius * 2.0,
                radius: radius
            )
        }
        guard let bounds = try resolvedSketchBounds2D(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Object dimensions require a finite sketch profile."
            )
        }
        return (
            sizeX: max(bounds.maxX - bounds.minX, 1.0e-9),
            sizeY: abs(depth),
            sizeZ: max(bounds.maxY - bounds.minY, 1.0e-9),
            radius: nil
        )
    }

    @discardableResult
    private mutating func appendSketchFeature(
        name: String,
        sketch: Sketch,
        typeID: ObjectTypeID? = nil,
        geometryRole: ObjectDescriptor.GeometryRole = .sketchProfile,
        properties: ObjectPropertySet = ObjectPropertySet(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .sketch(sketch),
            outputs: [FeatureOutput(role: .profile)]
        )
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: name,
            reference: .sketch(featureID),
            object: .sketch(
                featureID: featureID,
                typeID: typeID,
                geometryRole: geometryRole,
                properties: properties,
                objectRegistry: objectRegistry
            )
        )
        appendFeature(feature)
        return featureID
    }

    private func resolvedLengthValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    private func resolvedPositiveLengthValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let value = try resolvedLengthValue(expression, owner: owner)
        guard value > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be greater than zero."
            )
        }
        return value
    }

    private func rectangleSketch(
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) -> Sketch {
        let bottom = SketchEntityID()
        let right = SketchEntityID()
        let top = SketchEntityID()
        let left = SketchEntityID()
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        return Sketch(
            plane: plane,
            entities: [
                bottom: .line(SketchLine(start: bottomLeft, end: bottomRight)),
                right: .line(SketchLine(start: bottomRight, end: topRight)),
                top: .line(SketchLine(start: topRight, end: topLeft)),
                left: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ],
            constraints: [
                .horizontal(bottom),
                .vertical(right),
                .horizontal(top),
                .vertical(left),
                .coincident(.lineEnd(bottom), .lineStart(right)),
                .coincident(.lineEnd(right), .lineStart(top)),
                .coincident(.lineEnd(top), .lineStart(left)),
                .coincident(.lineEnd(left), .lineStart(bottom)),
            ]
        )
    }

    private func updateRectangleSketch(
        _ sketch: inout Sketch,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) throws {
        guard let lineIDs = try rectangleLineIDs(in: sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an axis-aligned rectangle profile."
            )
        }
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        sketch.entities[lineIDs.bottom] = .line(SketchLine(start: bottomLeft, end: bottomRight))
        sketch.entities[lineIDs.right] = .line(SketchLine(start: bottomRight, end: topRight))
        sketch.entities[lineIDs.top] = .line(SketchLine(start: topRight, end: topLeft))
        sketch.entities[lineIDs.left] = .line(SketchLine(start: topLeft, end: bottomLeft))
    }

    private func rectangleLineIDs(
        in sketch: Sketch
    ) throws -> (bottom: SketchEntityID, right: SketchEntityID, top: SketchEntityID, left: SketchEntityID)? {
        guard let bounds = try resolvedSketchBounds2D(sketch),
              sketch.entities.count == 4 else {
            return nil
        }
        var bottom: SketchEntityID?
        var right: SketchEntityID?
        var top: SketchEntityID?
        var left: SketchEntityID?
        let tolerance = 1.0e-9

        for (id, entity) in sketch.entities {
            guard case .line(let line) = entity else {
                return nil
            }
            let startX = try resolvedLengthValue(line.start.x, owner: "Rectangle line start x")
            let startY = try resolvedLengthValue(line.start.y, owner: "Rectangle line start y")
            let endX = try resolvedLengthValue(line.end.x, owner: "Rectangle line end x")
            let endY = try resolvedLengthValue(line.end.y, owner: "Rectangle line end y")
            if nearlyEqual(startY, bounds.minY, tolerance: tolerance),
               nearlyEqual(endY, bounds.minY, tolerance: tolerance) {
                bottom = id
            } else if nearlyEqual(startY, bounds.maxY, tolerance: tolerance),
                      nearlyEqual(endY, bounds.maxY, tolerance: tolerance) {
                top = id
            } else if nearlyEqual(startX, bounds.minX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.minX, tolerance: tolerance) {
                left = id
            } else if nearlyEqual(startX, bounds.maxX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.maxX, tolerance: tolerance) {
                right = id
            } else {
                return nil
            }
        }

        guard let bottom,
              let right,
              let top,
              let left else {
            return nil
        }
        return (bottom, right, top, left)
    }

    private func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func resolvedSketchBounds2D(
        _ sketch: Sketch
    ) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var points: [(x: Double, y: Double)] = []
        for entity in sketch.entities.values {
            for point in sketchPoints(in: entity) {
                points.append(
                    (
                        x: try resolvedLengthValue(point.x, owner: "Sketch point x"),
                        y: try resolvedLengthValue(point.y, owner: "Sketch point y")
                    )
                )
            }
        }
        guard let first = points.first else {
            return nil
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return (minX, minY, maxX, maxY)
    }

    private func sketchPoints(in entity: SketchEntity) -> [SketchPoint] {
        switch entity {
        case .point(let point):
            [point]
        case .line(let line):
            [line.start, line.end]
        case .circle(let circle):
            [circle.center]
        }
    }

    private func isRectangleProfile(_ sketch: Sketch) -> Bool {
        guard sketch.entities.count == 4 else {
            return false
        }
        return sketch.entities.values.allSatisfy { entity in
            if case .line(_) = entity {
                return true
            }
            return false
        }
    }

    private func singleCircleEntry(in sketch: Sketch) -> (id: SketchEntityID, circle: SketchCircle)? {
        var circleEntry: (id: SketchEntityID, circle: SketchCircle)?
        for (id, entity) in sketch.entities {
            guard case .circle(let circle) = entity else {
                return nil
            }
            guard circleEntry == nil else {
                return nil
            }
            circleEntry = (id, circle)
        }
        return circleEntry
    }

    @discardableResult
    public mutating func extrudeProfile(
        name: String,
        profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection,
        typeID: ObjectTypeID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        try profile.validate()
        guard let source = cadDocument.designGraph.nodes[profile.featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude profile must reference an existing sketch profile feature."
            )
        }
        guard source.containsSupportedExtrudeProfile else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude profile must reference a supported closed sketch profile."
            )
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .extrude(
                ExtrudeFeature(
                    profile: profile,
                    distance: distance,
                    direction: direction,
                    operation: .newBody
                )
            ),
            inputs: [FeatureInput(featureID: profile.featureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: name,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceProfileFeatureID: profile.featureID,
                typeID: typeID,
                objectRegistry: objectRegistry
            )
        )
        appendFeature(feature)
        cadDocument.designGraph.dependencies.append(
            DependencyEdge(source: profile.featureID, target: featureID)
        )
        try synchronizeObjectPropertiesFromSource(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        return featureID
    }

    public mutating func createExtrudedRectangle(
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let sketchFeatureID = try createRectangleSketch(
            name: "\(name) Sketch",
            plane: plane,
            width: width,
            height: height,
            objectRegistry: objectRegistry
        )
        try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction,
            typeID: .cube,
            objectRegistry: objectRegistry
        )
    }

    public mutating func createExtrudedRectangleFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression,
        direction: ExtrudeDirection,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let sketchFeatureID = try createRectangleSketchFromCorners(
            name: "\(name) Sketch",
            plane: plane,
            firstCorner: firstCorner,
            oppositeCorner: oppositeCorner,
            objectRegistry: objectRegistry
        )
        try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction,
            typeID: .cube,
            objectRegistry: objectRegistry
        )
    }

    public mutating func createExtrudedCircle(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let sketchFeatureID = try createCircleSketch(
            name: "\(name) Sketch",
            plane: plane,
            center: center,
            radius: radius,
            objectRegistry: objectRegistry
        )
        try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction,
            typeID: .cylinder,
            objectRegistry: objectRegistry
        )
    }

    public func validate(objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        try cadDocument.validate()
        try ruler.validate()
        guard ruler.displayUnit == displayUnit else {
            throw DocumentValidationError.invalidProductMetadata(
                "Document ruler display unit must match the document display unit."
            )
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private mutating func appendFeature(_ feature: FeatureNode) {
        cadDocument.designGraph.nodes[feature.id] = feature
        cadDocument.designGraph.order.append(feature.id)
        cadDocument.designGraph.revision = cadDocument.designGraph.revision.advanced()
    }

    private func normalizedMetadataName(
        _ name: String,
        owner: String
    ) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) names must not be empty."
            )
        }
        return trimmedName
    }
}

private extension FeatureNode {
    var containsSupportedExtrudeProfile: Bool {
        guard case .sketch(let sketch) = operation else {
            return false
        }
        return sketch.containsClosedLineLoop || sketch.containsSingleCircleProfile
    }
}

private extension Sketch {
    var containsClosedLineLoop: Bool {
        let lines = entities.values.compactMap(\.line)
        guard lines.count >= 3 else {
            return false
        }

        var pointDegrees: [SketchPoint: Int] = [:]
        for line in lines {
            pointDegrees[line.start, default: 0] += 1
            pointDegrees[line.end, default: 0] += 1
        }
        return pointDegrees.values.allSatisfy { $0 == 2 }
    }

    var containsSingleCircleProfile: Bool {
        let circles = entities.values.compactMap(\.circle)
        return circles.count == 1 && entities.count == 1
    }
}

private extension SketchEntity {
    var line: SketchLine? {
        if case .line(let line) = self {
            return line
        }
        return nil
    }

    var circle: SketchCircle? {
        if case .circle(let circle) = self {
            return circle
        }
        return nil
    }
}
