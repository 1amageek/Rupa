import Foundation
import SwiftCAD

public struct DesignDocument: Identifiable, Sendable {
    private typealias EditableProfileRegionSelection = (
        featureID: FeatureID,
        profileIndex: Int,
        feature: FeatureNode,
        sketch: Sketch,
        profile: Profile
    )
    private typealias PlannedOffsetRegionFeature = (
        name: String,
        result: OffsetRegionBuilder.Result
    )
    private typealias EditableSketchEntitySelection = (
        featureID: FeatureID,
        entityID: SketchEntityID,
        feature: FeatureNode,
        sketch: Sketch,
        entity: SketchEntity
    )

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
        kind: QuantityKind,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var updatedCADDocument = cadDocument
        updatedCADDocument.upsertParameter(
            name: name,
            expression: expression,
            kind: kind
        )
        cadDocument = updatedCADDocument
        do {
            try regeneratePatternArrays(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            productMetadata = previousProductMetadata
            throw error
        }
    }

    public mutating func deleteParameter(
        name: String,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard cadDocument.parameterID(named: name) != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Parameter delete requires an existing parameter."
            )
        }

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.deleteParameter(named: name)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Parameter \(name) is still referenced: \(error)."
            )
        }
        cadDocument = updatedCADDocument
        do {
            try regeneratePatternArrays(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            productMetadata = previousProductMetadata
            throw error
        }
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
            guard patternArraySourceID(containingOutputSceneNode: rootSceneNodeID) == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Component definitions cannot use source-owned pattern array output scene nodes."
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

    @discardableResult
    public mutating func createPatternArray(
        name: String,
        definitionID: ComponentDefinitionID,
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode = .componentInstance,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> PatternArraySourceID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Pattern array"
        )
        try distribution.validate()
        guard productMetadata.patternArrays.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array source names must be unique."
            )
        }
        _ = try requireRenderablePatternArrayDefinition(
            definitionID,
            metadata: productMetadata
        )

        switch outputMode {
        case .componentInstance, .independentCopy:
            break
        }

        var updatedCADDocument = cadDocument
        var updatedMetadata = productMetadata
        guard let rootSceneNodeID = updatedMetadata.rootSceneNodeIDs.first,
              updatedMetadata.sceneNodes[rootSceneNodeID] != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern arrays require a valid root scene node."
            )
        }

        let groupNode = SceneNode(
            name: trimmedName,
            object: .group()
        )
        updatedMetadata.sceneNodes[groupNode.id] = groupNode
        updatedMetadata.sceneNodes[rootSceneNodeID]?.childIDs.append(groupNode.id)

        let source = PatternArraySource(
            name: trimmedName,
            definitionID: definitionID,
            distribution: distribution,
            outputMode: outputMode,
            outputInstanceIDs: [],
            rootSceneNodeID: groupNode.id
        )
        updatedMetadata.patternArrays[source.id] = source
        try synchronizePatternArrayOutputs(
            for: source.id,
            metadata: &updatedMetadata,
            cadDocument: &updatedCADDocument
        )
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
        return source.id
    }

    public mutating func updatePatternArray(
        id: PatternArraySourceID,
        name: String? = nil,
        definitionID: ComponentDefinitionID? = nil,
        distribution: PatternArrayDistribution? = nil,
        outputMode: PatternArrayOutputMode? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        var updatedCADDocument = cadDocument
        var updatedMetadata = productMetadata
        guard var source = updatedMetadata.patternArrays[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array update requires an existing pattern source."
            )
        }

        if let name {
            let trimmedName = try normalizedMetadataName(
                name,
                owner: "Pattern array"
            )
            guard updatedMetadata.patternArrays.values.allSatisfy({
                $0.id == id || $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
            }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Pattern array source names must be unique."
                )
            }
            source.name = trimmedName
            guard var rootNode = updatedMetadata.sceneNodes[source.rootSceneNodeID],
                  rootNode.reference == nil,
                  rootNode.object?.category == .group else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array update requires an existing output group scene node."
                )
            }
            rootNode.name = trimmedName
            updatedMetadata.sceneNodes[source.rootSceneNodeID] = rootNode
        }

        let nextDefinitionID = definitionID ?? source.definitionID
        let definition = try requireRenderablePatternArrayDefinition(
            nextDefinitionID,
            metadata: updatedMetadata
        )
        source.definitionID = definition.id

        if let distribution {
            try distribution.validate()
            source.distribution = distribution
        }

        let nextOutputMode = outputMode ?? source.outputMode
        switch nextOutputMode {
        case .componentInstance, .independentCopy:
            break
        }
        source.outputMode = nextOutputMode

        let previousSource = updatedMetadata.patternArrays[id]
        updatedMetadata.patternArrays[id] = source
        try synchronizePatternArrayOutputs(
            for: id,
            previousSource: previousSource,
            metadata: &updatedMetadata,
            cadDocument: &updatedCADDocument
        )
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
    }

    @discardableResult
    public mutating func explodePatternArray(
        id: PatternArraySourceID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> PatternArrayExplodeResult {
        var updatedCADDocument = cadDocument
        var updatedMetadata = productMetadata
        guard let source = updatedMetadata.patternArrays[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array explode requires an existing pattern source."
            )
        }
        guard updatedMetadata.sceneNodes[source.rootSceneNodeID] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array explode requires an existing output group scene node."
            )
        }

        let result = try materializedPatternArrayOutputsForExplode(
            source: source,
            metadata: &updatedMetadata,
            cadDocument: &updatedCADDocument
        )
        updatedMetadata.patternArrays.removeValue(forKey: id)
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
        return result
    }

    public mutating func regeneratePatternArrays(
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard productMetadata.patternArrays.isEmpty == false else {
            return
        }
        var updatedCADDocument = cadDocument
        var updatedMetadata = productMetadata
        let sourceIDs = updatedMetadata.patternArrays.keys.sorted {
            $0.description < $1.description
        }
        for sourceID in sourceIDs {
            try synchronizePatternArrayOutputs(
                for: sourceID,
                metadata: &updatedMetadata,
                cadDocument: &updatedCADDocument
            )
        }
        try updatedMetadata.validate(against: updatedCADDocument, objectRegistry: objectRegistry)
        cadDocument = updatedCADDocument
        productMetadata = updatedMetadata
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
        guard patternArraySourceID(containingGeneratedOutputSceneNode: id) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node visibility is controlled by the pattern source."
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
        guard patternArraySourceID(containingGeneratedOutputSceneNode: id) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node locks are controlled by the pattern source."
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
        guard patternArraySourceID(containingOutputSceneNode: id) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node transforms are controlled by the pattern source."
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
        guard patternArraySourceID(containingGeneratedOutputSceneNode: id) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node materials are controlled by the pattern source."
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
        guard patternArraySourceID(containingGeneratedOutputSceneNode: id) == nil else {
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
        guard patternArraySourceID(owningOutputInstance: id) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output instance visibility is controlled by the pattern source."
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
        guard patternArraySourceID(owningOutputInstance: id) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output instance locks are controlled by the pattern source."
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
        guard patternArraySourceID(owningOutputInstance: id) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output instance transforms are controlled by the pattern source."
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
    public mutating func createConstructionPlane(
        name: String,
        plane: SketchPlane,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Construction plane"
        )
        guard productMetadata.constructionPlanes.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Construction plane names must be unique."
            )
        }
        try ConstructionPlaneSource.validatePlane(plane)

        let source = ConstructionPlaneSource(
            name: trimmedName,
            plane: plane
        )
        productMetadata.constructionPlanes[source.id] = source
        if activates {
            productMetadata.activeConstructionPlaneID = source.id
        }
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .constructionPlane(source.id),
            object: .construction()
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return source.id
    }

    public mutating func setActiveConstructionPlane(
        id: ConstructionPlaneSourceID?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        if let id,
           productMetadata.constructionPlanes[id] == nil {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Active construction plane requires an existing construction plane source."
            )
        }
        productMetadata.activeConstructionPlaneID = id
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func addMeasurementAnnotation(
        _ annotation: MeasurementAnnotation,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> MeasurementAnnotationID {
        var nextAnnotation = annotation
        nextAnnotation.name = try normalizedMetadataName(
            annotation.name,
            owner: "Measurement annotation"
        )
        var metadata = productMetadata
        guard metadata.measurements[nextAnnotation.id] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Measurement annotation IDs must be unique."
            )
        }
        if let sceneNodeID = nextAnnotation.sceneNodeID {
            guard metadata.sceneNodes[sceneNodeID]?.object?.category == .annotation else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Measurement annotation scene node must exist and use an annotation object."
                )
            }
        } else {
            let sceneNodeID = try metadata.appendSceneNodeToFirstRoot(
                name: nextAnnotation.name,
                reference: nil,
                object: .annotation()
            )
            nextAnnotation.sceneNodeID = sceneNodeID
        }
        metadata.measurements[nextAnnotation.id] = nextAnnotation
        try metadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = metadata
        return nextAnnotation.id
    }

    public mutating func renameConstructionPlane(
        id: ConstructionPlaneSourceID,
        name: String,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Construction plane"
        )
        guard var source = productMetadata.constructionPlanes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Construction plane rename requires an existing construction plane source."
            )
        }
        guard productMetadata.constructionPlanes.values.allSatisfy({
            $0.id == id || $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Construction plane names must be unique."
            )
        }

        source.name = trimmedName
        productMetadata.constructionPlanes[id] = source
        for (nodeID, node) in productMetadata.sceneNodes where node.reference?.constructionPlaneID == id {
            var updatedNode = node
            updatedNode.name = trimmedName
            productMetadata.sceneNodes[nodeID] = updatedNode
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func createConstructionPlaneFromTarget(
        name: String,
        target: SelectionTarget,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let plane = try ConstructionPlaneTargetResolver().plane(
            alignedTo: target,
            in: self,
            objectRegistry: objectRegistry
        )
        return try createConstructionPlane(
            name: name,
            plane: plane,
            activates: activates,
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createConstructionPlaneFromTargets(
        name: String,
        targets: [SelectionTarget],
        viewNormal: Vector3D? = nil,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let plane = try ConstructionPlaneTargetResolver().plane(
            from: targets,
            in: self,
            viewNormal: viewNormal,
            objectRegistry: objectRegistry
        )
        return try createConstructionPlane(
            name: name,
            plane: plane,
            activates: activates,
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createViewAlignedConstructionPlane(
        name: String,
        origin: Point3D = .origin,
        viewNormal: Vector3D,
        activates: Bool = true,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ConstructionPlaneSourceID {
        let plane = try ConstructionPlaneViewResolver().plane(
            origin: origin,
            viewNormal: viewNormal
        )
        return try createConstructionPlane(
            name: name,
            plane: plane,
            activates: activates,
            objectRegistry: objectRegistry
        )
    }

    public var activeConstructionPlane: ConstructionPlaneSource? {
        guard let id = productMetadata.activeConstructionPlaneID else {
            return nil
        }
        return productMetadata.constructionPlanes[id]
    }

    public mutating func setCurveCurvatureDisplay(
        target: SelectionTarget,
        isVisible: Bool? = nil,
        combScale: Double? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let componentID = try curveCurvatureDisplayComponentID(for: target)
        let existing = productMetadata.curveCurvatureDisplays[componentID]
        let shouldShow = isVisible ?? (existing == nil)
        if shouldShow {
            let display = CurveCurvatureDisplay(
                componentID: componentID,
                combScale: combScale ?? existing?.combScale ?? CurveCurvatureDisplay.defaultCombScale
            )
            try display.validate(against: cadDocument)
            productMetadata.curveCurvatureDisplays[componentID] = display
        } else {
            productMetadata.curveCurvatureDisplays.removeValue(forKey: componentID)
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func setPointDisplay(
        target: SelectionTarget,
        isVisible: Bool? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let componentID = try pointDisplayComponentID(for: target)
        let existing = productMetadata.pointDisplays[componentID]
        let nextVisibility: Bool
        if let isVisible {
            nextVisibility = isVisible
        } else if let existing {
            nextVisibility = !existing.isVisible
        } else {
            nextVisibility = false
        }
        let display = PointDisplay(componentID: componentID, isVisible: nextVisibility)
        try display.validate(against: cadDocument)
        productMetadata.pointDisplays[componentID] = display
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func createSketch(
        name: String,
        sketch: Sketch,
        geometryRole: ObjectDescriptor.GeometryRole = .sketchProfile,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Sketch")
        guard sketch.entities.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch must contain at least one entity."
            )
        }
        guard geometryRole == .sketchProfile || geometryRole == .curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch geometry role must be sketchProfile or curve."
            )
        }
        try sketch.validate()
        try sketch.validateExpressions(using: cadDocument.parameters)
        return try appendSketchFeature(
            name: trimmedName,
            sketch: sketch,
            geometryRole: geometryRole,
            objectRegistry: objectRegistry
        )
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
                "angle": .angle(
                    Self.normalizedAngleDegrees(atan2(deltaY, deltaX) * 180.0 / .pi)
                ),
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
    public mutating func createArcSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        startAngle: CADExpression,
        endAngle: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedRadius = try resolvedLengthValue(radius, owner: "Arc radius")
        guard resolvedRadius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch radius must be greater than zero."
            )
        }
        let resolvedStartAngle = try resolvedAngleValue(startAngle, owner: "Arc start angle")
        let resolvedEndAngle = try resolvedAngleValue(endAngle, owner: "Arc end angle")
        let angleSpan = try normalizedPartialArcSpan(
            startAngle: resolvedStartAngle,
            endAngle: resolvedEndAngle
        )

        var builder = SketchBuilder(on: plane)
        builder.arc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle
        )
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .arc,
            geometryRole: .curve,
            properties: ObjectPropertySet(values: [
                "radius": .length(resolvedRadius),
                "start.angle": .angle(
                    Self.normalizedAngleDegrees(resolvedStartAngle * 180.0 / .pi)
                ),
                "end.angle": .angle(
                    Self.normalizedAngleDegrees((resolvedStartAngle + angleSpan) * 180.0 / .pi)
                ),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createSplineSketch(
        name: String,
        plane: SketchPlane,
        spline: SketchSpline,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        try validateSpline(spline, owner: "Spline sketch")

        var builder = SketchBuilder(on: plane)
        builder.spline(spline)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .spline,
            geometryRole: .curve,
            properties: ObjectPropertySet(values: [
                "control.point.count": .integer(spline.controlPoints.count),
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

    @discardableResult
    public mutating func createPolygonSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        sides: Int,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        rotationAngle: CADExpression = .angle(0.0, .radian),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        _ = try resolvedLengthValue(center.x, owner: "Polygon center x")
        _ = try resolvedLengthValue(center.y, owner: "Polygon center y")
        let resolvedRadius = try resolvedLengthValue(radius, owner: "Polygon radius")
        guard resolvedRadius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Polygon sketch radius must be greater than zero."
            )
        }
        try validatePolygonSides(sides)
        let resolvedRotationAngle = try resolvedAngleValue(rotationAngle, owner: "Polygon rotation angle")
        let resolvedCircumradius = sizingMode.circumradius(from: resolvedRadius, sides: sides)
        let sideLength = sizingMode.sideLength(from: resolvedRadius, sides: sides)
        let sketch = polygonSketch(
            plane: plane,
            center: center,
            radius: polygonCircumradiusExpression(
                radius,
                sides: sides,
                sizingMode: sizingMode
            ),
            sides: sides,
            rotationAngle: rotationAngle
        )

        return try appendSketchFeature(
            name: name,
            sketch: sketch,
            typeID: .polygon,
            properties: ObjectPropertySet(values: [
                "radius": .length(resolvedCircumradius),
                "sizing.radius": .length(resolvedRadius),
                "radius.is.inradius": .boolean(sizingMode == .inradius),
                "inclination.mode": .text(inclinationMode.rawValue),
                "sides.x": .integer(sides),
                "angle": .angle(
                    Self.normalizedAngleDegrees(resolvedRotationAngle * 180.0 / .pi)
                ),
                "side.length": .length(sideLength),
            ]),
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func createFaceKnife(
        name: String,
        target: SelectionTarget,
        loop: [Point3D],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Face Knife"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        guard case .face(let componentID) = target.component,
              let persistentNameString = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology face target."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        let sceneNode = resolvedTarget.sceneNode
        let targetFeatureID = resolvedTarget.featureID
        guard let targetFeature = cadDocument.designGraph.nodes[targetFeatureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentNameString }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face was not found in the current evaluation."
            )
        }
        guard entry.kind == .face,
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target must reference a face on the selected body."
            )
        }

        let facePersistentName = try GeneratedTopologyPersistentNameParser().parse(
            persistentNameString,
            operationName: operationName
        )
        let faceKnife = FaceKnifeFeature(
            target: FaceKnifeTargetReference(featureID: targetFeatureID),
            facePersistentName: facePersistentName,
            loop: loop
        )
        try faceKnife.validate()

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .faceKnife(faceKnife),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: nil,
                geometryRole: sceneNode.object?.geometryRole ?? .solid,
                properties: ObjectPropertySet(),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommit = true
        return featureID
    }

    @discardableResult
    public mutating func createSlotSketch(
        target: SelectionTarget,
        width: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedWidth = try resolvedPositiveLengthValue(width, owner: "Slot width")
        let selection = try editableSketchEntity(for: target, operationName: "Slot")
        let name = "\(selection.feature.name ?? "Sketch Curve") Slot"

        switch selection.entity {
        case .line:
            let curveChain = try slotCurveChainPathSegments(for: selection)
            let result = try curveChain.allSatisfy(\.isLineSegment)
                ? SlotProfileBuilder().buildLineChainSlot(
                    points: slotLineChainPathPoints(for: selection),
                    plane: selection.sketch.plane,
                    width: width,
                    resolvedWidth: resolvedWidth
                )
                : SlotProfileBuilder().buildCurveChainSlot(
                    segments: curveChain,
                    plane: selection.sketch.plane,
                    width: width,
                    resolvedWidth: resolvedWidth
                )
            return try appendSketchFeature(
                name: name,
                sketch: result.sketch,
                typeID: .slot,
                geometryRole: .sketchProfile,
                properties: ObjectPropertySet(values: [
                    "width": .length(result.width),
                    "path.length": .length(result.pathLength),
                    "radius": .length(result.capRadius),
                    ProfileTessellationPolicy.arcSegmentsPropertyID: .integer(32),
                ]),
                objectRegistry: objectRegistry
            )
        case .arc(let arc):
            let curveChain = try slotCurveChainPathSegments(for: selection)
            let result = try curveChain.count == 1
                ? SlotProfileBuilder().buildArcSlot(
                    source: arc,
                    plane: selection.sketch.plane,
                    resolvedRadius: resolvedPositiveLengthValue(arc.radius, owner: "Slot source arc radius"),
                    resolvedStartAngle: resolvedAngleValue(arc.startAngle, owner: "Slot source arc start angle"),
                    resolvedEndAngle: resolvedAngleValue(arc.endAngle, owner: "Slot source arc end angle"),
                    width: width,
                    resolvedWidth: resolvedWidth
                )
                : SlotProfileBuilder().buildCurveChainSlot(
                    segments: curveChain,
                    plane: selection.sketch.plane,
                    width: width,
                    resolvedWidth: resolvedWidth
                )
            return try appendSketchFeature(
                name: name,
                sketch: result.sketch,
                typeID: .slot,
                geometryRole: .sketchProfile,
                properties: ObjectPropertySet(values: [
                    "width": .length(result.width),
                    "path.length": .length(result.pathLength),
                    "radius": .length(result.capRadius),
                    ProfileTessellationPolicy.arcSegmentsPropertyID: .integer(32),
                ]),
                objectRegistry: objectRegistry
            )
        case .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Slot supports selected source line, connected open source line-chain, open source arc, and connected open line/arc chain targets; spline slots require joined curve offset support before mutation."
            )
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; circle targets are closed."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve target, not a point."
            )
        }
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

        var candidateSketch = sketch
        candidateSketch.constraints.append(constraint)
        var candidateFeature = feature
        candidateFeature.operation = .sketch(candidateSketch)
        var candidateCADDocument = cadDocument
        do {
            try candidateCADDocument.replaceFeature(candidateFeature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint references invalid geometry: \(error)."
            )
        }

        let constraintPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        try constraintPropagator.satisfyAddingConstraint(
            constraint,
            in: &sketch,
            owner: "Sketch constraint"
        )
        feature.operation = .sketch(sketch)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch constraint references invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeSketchObjectProperties(
            featureID: featureID,
            sketch: sketch,
            objectRegistry: objectRegistry
        )
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func createBridgeCurve(
        featureID: FeatureID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        continuity: BridgeCurveContinuity,
        trimsSourceCurves: Bool = false,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let firstTension = try resolvedBridgeTension(
            firstEndpoint.tension,
            owner: "Bridge curve first tension"
        )
        let secondTension = try resolvedBridgeTension(
            secondEndpoint.tension,
            owner: "Bridge curve second tension"
        )
        let resolver = SketchCurveEndpointResolver()
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve requires an editable sketch feature."
            )
        }
        var nextFirstEndpoint = firstEndpoint
        var nextSecondEndpoint = secondEndpoint
        if trimsSourceCurves {
            try validateBridgeCurveTrimDistinctSourceEntities(
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint
            )
            nextFirstEndpoint = try trimBridgeCurveSourceEndpoint(
                firstEndpoint,
                in: &sketch,
                owner: "Bridge curve first trim"
            )
            nextSecondEndpoint = try trimBridgeCurveSourceEndpoint(
                secondEndpoint,
                in: &sketch,
                owner: "Bridge curve second trim"
            )
        }
        guard let firstSample = try resolver.sample(
            for: nextFirstEndpoint,
            sketch: sketch,
            document: self
        ),
        let secondSample = try resolver.sample(
            for: nextSecondEndpoint,
            sketch: sketch,
            document: self
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
            )
        }
        try validateDistinctBridgeEndpointSamples(first: firstSample, second: secondSample)
        try validateBridgeContinuitySupport(
            first: firstSample,
            second: secondSample,
            continuity: continuity
        )

        let controlPoints = bridgeControlPoints(
            first: firstSample,
            firstTension: firstTension,
            second: secondSample,
            secondTension: secondTension
        )
        let spline = SketchSpline(controlPoints: controlPoints)
        try validateSpline(spline, owner: "Bridge curve")

        let bridgeID = SketchEntityID()
        sketch.entities[bridgeID] = .spline(spline)
        for constraint in bridgeOwnedConstraints(
            bridgeID: bridgeID,
            firstEndpoint: nextFirstEndpoint,
            secondEndpoint: nextSecondEndpoint,
            firstSample: firstSample,
            secondSample: secondSample,
            continuity: continuity
        ) {
            appendBridgeConstraint(constraint, to: &sketch)
        }
        let bridgeSource = BridgeCurveSource(
            featureID: featureID,
            entityID: bridgeID,
            firstEndpoint: nextFirstEndpoint,
            secondEndpoint: nextSecondEndpoint,
            continuity: continuity,
            trimsSourceCurves: trimsSourceCurves
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitBridgeCurve = false
        defer {
            if didCommitBridgeCurve == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources[bridgeSource.id] = bridgeSource

        if sketch.entities.count == 1 {
            try setSketchObjectType(
                featureID: featureID,
                typeID: .spline,
                objectRegistry: objectRegistry
            )
        } else {
            try markSketchObjectAsSourceEdited(featureID: featureID)
        }
        try commitSketchEntityEdit(
            featureID: featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Bridge curve creation"
        )
        didCommitBridgeCurve = true
        return bridgeID
    }

    public mutating func setBridgeCurveParameters(
        sourceID: BridgeCurveSourceID,
        firstEndpoint: BridgeCurveEndpoint? = nil,
        secondEndpoint: BridgeCurveEndpoint? = nil,
        continuity: BridgeCurveContinuity? = nil,
        trimsSourceCurves: Bool? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard let source = productMetadata.bridgeCurveSources[sourceID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve source could not be resolved."
            )
        }
        if let trimsSourceCurves,
           trimsSourceCurves == false,
           source.trimsSourceCurves {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve trim cannot be disabled after source curves have been trimmed."
            )
        }
        let nextSource = BridgeCurveSource(
            id: source.id,
            featureID: source.featureID,
            entityID: source.entityID,
            firstEndpoint: firstEndpoint ?? source.firstEndpoint,
            secondEndpoint: secondEndpoint ?? source.secondEndpoint,
            continuity: continuity ?? source.continuity,
            trimsSourceCurves: trimsSourceCurves ?? source.trimsSourceCurves
        )
        let firstTension = try resolvedBridgeTension(
            nextSource.firstEndpoint.tension,
            owner: "Bridge curve first tension"
        )
        let secondTension = try resolvedBridgeTension(
            nextSource.secondEndpoint.tension,
            owner: "Bridge curve second tension"
        )
        let resolver = SketchCurveEndpointResolver()
        guard bridgeEndpointReferencesEntity(nextSource.firstEndpoint, entityID: source.entityID) == false,
              bridgeEndpointReferencesEntity(nextSource.secondEndpoint, entityID: source.entityID) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoints must not reference the generated bridge spline."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[source.featureID],
              case var .sketch(sketch) = feature.operation,
              case .spline = sketch.entities[source.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve source must point to an editable generated spline."
            )
        }
        guard let previousFirstSample = try resolver.sample(
            for: source.firstEndpoint,
            sketch: sketch,
            document: self
        ),
        let previousSecondSample = try resolver.sample(
            for: source.secondEndpoint,
            sketch: sketch,
            document: self
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
            )
        }
        let previousConstraints = bridgeOwnedConstraints(
            bridgeID: source.entityID,
            firstEndpoint: source.firstEndpoint,
            secondEndpoint: source.secondEndpoint,
            firstSample: previousFirstSample,
            secondSample: previousSecondSample,
            continuity: source.continuity
        )
        sketch.constraints.removeAll { previousConstraints.contains($0) }
        var resolvedNextSource = nextSource
        if resolvedNextSource.trimsSourceCurves {
            try validateBridgeCurveTrimDistinctSourceEntities(
                firstEndpoint: resolvedNextSource.firstEndpoint,
                secondEndpoint: resolvedNextSource.secondEndpoint
            )
            resolvedNextSource.firstEndpoint = try trimBridgeCurveSourceEndpoint(
                resolvedNextSource.firstEndpoint,
                in: &sketch,
                owner: "Bridge curve first trim"
            )
            resolvedNextSource.secondEndpoint = try trimBridgeCurveSourceEndpoint(
                resolvedNextSource.secondEndpoint,
                in: &sketch,
                owner: "Bridge curve second trim"
            )
        }
        guard let firstSample = try resolver.sample(
            for: resolvedNextSource.firstEndpoint,
            sketch: sketch,
            document: self
        ),
        let secondSample = try resolver.sample(
            for: resolvedNextSource.secondEndpoint,
            sketch: sketch,
            document: self
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
            )
        }
        try validateDistinctBridgeEndpointSamples(first: firstSample, second: secondSample)
        try validateBridgeContinuitySupport(
            first: firstSample,
            second: secondSample,
            continuity: resolvedNextSource.continuity
        )

        let spline = SketchSpline(controlPoints: bridgeControlPoints(
            first: firstSample,
            firstTension: firstTension,
            second: secondSample,
            secondTension: secondTension
        ))
        try validateSpline(spline, owner: "Bridge curve")

        sketch.entities[source.entityID] = .spline(spline)
        for constraint in bridgeOwnedConstraints(
            bridgeID: source.entityID,
            firstEndpoint: resolvedNextSource.firstEndpoint,
            secondEndpoint: resolvedNextSource.secondEndpoint,
            firstSample: firstSample,
            secondSample: secondSample,
            continuity: resolvedNextSource.continuity
        ) {
            appendBridgeConstraint(constraint, to: &sketch)
        }

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitBridgeCurveUpdate = false
        defer {
            if didCommitBridgeCurveUpdate == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources[sourceID] = resolvedNextSource
        try commitSketchEntityEdit(
            featureID: source.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Bridge curve parameter update"
        )
        didCommitBridgeCurveUpdate = true
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
        do {
            try updatedCADDocument.replaceFeature(feature)
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
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
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
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
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

    public mutating func setObjectDimension(
        target: SelectionTarget,
        kind: ObjectDimensionKind,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let source = try ObjectDimensionSourceResolver().resolve(target: target, in: self)
        let dimensions = (
            sizeX: source.sizeX,
            sizeY: source.sizeY,
            sizeZ: source.sizeZ,
            radius: source.radius
        )
        if source.shape == .cylinder {
            try setCylinderObjectDimension(
                featureID: source.featureID,
                currentDimensions: dimensions,
                kind: kind,
                value: value,
                objectRegistry: objectRegistry
            )
            return
        }

        try setBoxObjectDimension(
            featureID: source.featureID,
            currentDimensions: dimensions,
            kind: kind,
            value: value,
            objectRegistry: objectRegistry
        )
    }

    private mutating func setBoxObjectDimension(
        featureID: FeatureID,
        currentDimensions: (sizeX: Double, sizeY: Double, sizeZ: Double, radius: Double?),
        kind: ObjectDimensionKind,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard kind == .sizeX || kind == .sizeY || kind == .sizeZ else {
            throw EditorError(
                code: .commandInvalid,
                message: "Box object dimension supports sizeX, sizeY, or sizeZ."
            )
        }
        try setCubeDimensions(
            featureID: featureID,
            sizeX: kind == .sizeX ? value : .length(currentDimensions.sizeX, .meter),
            sizeY: kind == .sizeY ? value : .length(currentDimensions.sizeY, .meter),
            sizeZ: kind == .sizeZ ? value : .length(currentDimensions.sizeZ, .meter),
            objectRegistry: objectRegistry
        )
    }

    private mutating func setCylinderObjectDimension(
        featureID: FeatureID,
        currentDimensions: (sizeX: Double, sizeY: Double, sizeZ: Double, radius: Double?),
        kind: ObjectDimensionKind,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let currentRadius = currentDimensions.radius ?? max(currentDimensions.sizeX, currentDimensions.sizeZ) / 2.0
        let nextRadius: CADExpression
        let nextSizeY: CADExpression
        switch kind {
        case .radius:
            _ = try resolvedPositiveLengthValue(value, owner: "Object radius dimension")
            nextRadius = value
            nextSizeY = .length(currentDimensions.sizeY, .meter)
        case .diameter, .sizeX, .sizeZ:
            let diameter = try resolvedPositiveLengthValue(value, owner: "Object diameter dimension")
            nextRadius = .length(diameter / 2.0, .meter)
            nextSizeY = .length(currentDimensions.sizeY, .meter)
        case .sizeY:
            _ = try resolvedPositiveLengthValue(value, owner: "Object depth dimension")
            nextRadius = .length(currentRadius, .meter)
            nextSizeY = value
        }
        try setCylinderDimensions(
            featureID: featureID,
            radius: nextRadius,
            sizeY: nextSizeY,
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func offsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        if options.mode == .slot {
            let featureID = try createSlotFromOffsetCurve(
                target: target,
                width: distance,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return [featureID]
        }
        let distanceMeters = try resolvedLengthValue(distance, owner: "Curve offset distance")
        guard abs(distanceMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Curve offset distance must not be zero."
            )
        }
        if options.supportTarget != nil {
            guard case .edge = target.component else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve offset support target is only valid for generated edge Offset Edge dispatch."
                )
            }
        }

        switch target.component {
        case .sketchEntity:
            let selection = try editableSketchEntity(for: target, operationName: "Curve offset")
            if let vertexHandle {
                try validateOffsetCurveVertexOptions(options)
                try offsetSketchVertex(
                    target: target,
                    handle: vertexHandle,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                return [selection.featureID]
            }
            let name = "\(selection.feature.name ?? "Sketch Curve") Offset"
            switch selection.entity {
            case .line(let line):
                let shiftedLine = try offsetLine(
                    line,
                    distance: distance,
                    owner: "Curve offset"
                )
                if options.isSymmetric {
                    let mirroredLine = try offsetLine(
                        line,
                        distance: negatedExpression(distance),
                        owner: "Curve offset"
                    )
                    let firstID = try createLineSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        start: shiftedLine.start,
                        end: shiftedLine.end,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createLineSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        start: mirroredLine.start,
                        end: mirroredLine.end,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createLineSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    start: shiftedLine.start,
                    end: shiftedLine.end,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .circle(let circle):
                let offsetRadius = try offsetRadiusExpression(
                    circle.radius,
                    distance: distance,
                    resolvedDistance: distanceMeters,
                    owner: "Curve offset circle"
                )
                if options.isSymmetric {
                    let mirroredRadius = try offsetRadiusExpression(
                        circle.radius,
                        distance: negatedExpression(distance),
                        resolvedDistance: -distanceMeters,
                        owner: "Curve offset circle"
                    )
                    let firstID = try createCircleSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        center: circle.center,
                        radius: offsetRadius,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createCircleSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        center: circle.center,
                        radius: mirroredRadius,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createCircleSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    center: circle.center,
                    radius: offsetRadius,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .arc(let arc):
                let offsetRadius = try offsetRadiusExpression(
                    arc.radius,
                    distance: distance,
                    resolvedDistance: distanceMeters,
                    owner: "Curve offset arc"
                )
                if options.isSymmetric {
                    let mirroredRadius = try offsetRadiusExpression(
                        arc.radius,
                        distance: negatedExpression(distance),
                        resolvedDistance: -distanceMeters,
                        owner: "Curve offset arc"
                    )
                    let firstID = try createArcSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        center: arc.center,
                        radius: offsetRadius,
                        startAngle: arc.startAngle,
                        endAngle: arc.endAngle,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createArcSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        center: arc.center,
                        radius: mirroredRadius,
                        startAngle: arc.startAngle,
                        endAngle: arc.endAngle,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createArcSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    center: arc.center,
                    radius: offsetRadius,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .point:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve offset source point entities do not identify the adjacent curve sides required by Offset Vertex. Select a source line or arc endpoint with a vertex handle."
                )
            case .spline:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Offset Planar Curve currently supports source line, circle, and arc sketch targets; spline offsets require joined curve offset support."
                )
            }
        case .region:
            let featureIDs = try offsetProfileRegion(
                target: target,
                distanceMeters: distanceMeters,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return featureIDs
        case .face:
            let featureID = try createFaceLoopOffsetFromOffsetCurve(
                target: target,
                distance: distance,
                distanceMeters: distanceMeters,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return [featureID]
        case .edge:
            let featureID = try createEdgeOffsetFromOffsetCurve(
                target: target,
                distance: distance,
                distanceMeters: distanceMeters,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return [featureID]
        case .vertex:
            guard vertexHandle == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Generated vertex Offset Vertex dispatch uses the selected generated vertex target and does not accept an additional sketch vertex handle."
                )
            }
            try validateOffsetCurveVertexOptions(options)
            let resolvedTarget = try generatedSketchVertexOffsetTarget(
                for: target,
                objectRegistry: objectRegistry
            )
            try offsetSketchVertex(
                target: resolvedTarget.target,
                handle: resolvedTarget.handle,
                distance: distance,
                objectRegistry: objectRegistry
            )
            return [resolvedTarget.featureID]
        case .object:
            throw EditorError(
                code: .referenceUnresolved,
                message: "Curve offset requires a selected curve, region, vertex, face loop, or edge target."
            )
        }
    }

    private struct GeneratedSketchVertexOffsetTarget {
        var featureID: FeatureID
        var target: SelectionTarget
        var handle: SketchEntityPointHandle
    }

    @discardableResult
    private mutating func createFaceLoopOffsetFromOffsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        distanceMeters: Double,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        let operationName = "Offset Face Loop"
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) uses the selected generated face target and does not accept a sketch vertex handle."
            )
        }
        guard options.isSymmetric == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports a single inward distance; symmetric lock-distance face-loop offsets are not implemented."
            )
        }
        guard distanceMeters > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports a positive inward distance."
            )
        }
        guard case .face(let componentID) = target.component,
              let persistentNameString = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology face target."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        let sceneNode = resolvedTarget.sceneNode
        let targetFeatureID = resolvedTarget.featureID
        guard let targetFeature = cadDocument.designGraph.nodes[targetFeatureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentNameString }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face was not found in the current evaluation."
            )
        }
        guard entry.kind == .face,
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target must reference a face on the selected body."
            )
        }

        let facePersistentName = try GeneratedTopologyPersistentNameParser().parse(
            persistentNameString,
            operationName: operationName
        )
        let featureID = FeatureID()
        let featureName = "\(sceneNode.name) Face Loop Offset"
        let feature = FeatureNode(
            id: featureID,
            name: featureName,
            operation: .faceLoopOffset(
                FaceLoopOffsetFeature(
                    target: FaceLoopOffsetTargetReference(featureID: targetFeatureID),
                    facePersistentName: facePersistentName,
                    distance: distance,
                    gapFill: options.gapFill.faceLoopOffsetGapFill
                )
            ),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: featureName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: nil,
                geometryRole: sceneNode.object?.geometryRole ?? .solid,
                properties: ObjectPropertySet(),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    @discardableResult
    private mutating func createEdgeOffsetFromOffsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        distanceMeters: Double,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        let operationName = "Offset Edge"
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) uses the selected generated edge target and does not accept a sketch vertex handle."
            )
        }
        guard distanceMeters > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports a positive inward distance."
            )
        }
        guard case .edge(let edgeComponentID) = target.component,
              let edgePersistentNameString = edgeComponentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology edge target."
            )
        }
        guard let supportTarget = options.supportTarget else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated support face target in offset options."
            )
        }
        guard case .face(let supportFaceComponentID) = supportTarget.component,
              let supportFacePersistentNameString = supportFaceComponentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology support face target."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        let resolvedSupportTarget = try editableBodyTargetResolution(
            for: supportTarget,
            operationName: operationName
        )
        guard resolvedSupportTarget.sceneNodeID == resolvedTarget.sceneNodeID else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target edge and support face must belong to the same body scene node."
            )
        }
        let sceneNode = resolvedTarget.sceneNode
        let targetFeatureID = resolvedTarget.featureID
        guard let targetFeature = cadDocument.designGraph.nodes[targetFeatureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        let evaluatedDocument = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self,
            objectRegistry: objectRegistry,
            failurePrefix: "\(operationName) requires current generated topology"
        )
        guard let edgeEntry = topology.entries.first(where: { $0.persistentName == edgePersistentNameString }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology edge was not found in the current evaluation."
            )
        }
        guard edgeEntry.kind == .edge,
              edgeEntry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target must reference an edge on the selected body."
            )
        }
        guard let supportFaceEntry = topology.entries.first(where: { $0.persistentName == supportFacePersistentNameString }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology support face was not found in the current evaluation."
            )
        }
        guard supportFaceEntry.kind == .face,
              supportFaceEntry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) support target must reference a face on the selected body."
            )
        }
        try validateEdgeOffsetSupportTopology(
            edgeEntry: edgeEntry,
            supportFaceEntry: supportFaceEntry,
            topology: topology,
            evaluatedDocument: evaluatedDocument,
            isSymmetric: options.isSymmetric,
            operationName: operationName
        )

        let edgePersistentName = try GeneratedTopologyPersistentNameParser().parse(
            edgePersistentNameString,
            operationName: operationName
        )
        let supportFacePersistentName = try GeneratedTopologyPersistentNameParser().parse(
            supportFacePersistentNameString,
            operationName: operationName
        )
        let featureID = FeatureID()
        let featureName = "\(sceneNode.name) Edge Offset"
        let feature = FeatureNode(
            id: featureID,
            name: featureName,
            operation: .edgeOffset(
                EdgeOffsetFeature(
                    target: EdgeOffsetTargetReference(featureID: targetFeatureID),
                    edgePersistentName: edgePersistentName,
                    supportFacePersistentName: supportFacePersistentName,
                    distance: distance,
                    isSymmetric: options.isSymmetric,
                    gapFill: options.gapFill.edgeOffsetGapFill
                )
            ),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: featureName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: nil,
                geometryRole: sceneNode.object?.geometryRole ?? .solid,
                properties: ObjectPropertySet(),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    private func validateEdgeOffsetSupportTopology(
        edgeEntry: TopologySummaryResult.Entry,
        supportFaceEntry: TopologySummaryResult.Entry,
        topology: TopologySummaryResult,
        evaluatedDocument: EvaluatedDocument,
        isSymmetric: Bool,
        operationName: String
    ) throws {
        guard edgeEntry.curveKind == "line",
              edgeEntry.start != nil,
              edgeEntry.end != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports generated line edges with resolvable endpoints."
            )
        }
        let edgeID = try evaluatedEdgeID(
            for: edgeEntry,
            in: evaluatedDocument,
            operationName: operationName
        )
        let supportFaceID = try evaluatedFaceID(
            for: supportFaceEntry,
            in: evaluatedDocument,
            operationName: operationName
        )
        guard face(supportFaceID, containsBoundaryEdge: edgeID, in: evaluatedDocument.brep) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) support face must contain the selected edge."
            )
        }
        guard isSymmetric else {
            return
        }
        let oppositeCandidates = try topology.entries.filter { entry in
            guard entry.kind == .face,
                  entry.sceneNodeID == edgeEntry.sceneNodeID,
                  entry.persistentName != supportFaceEntry.persistentName else {
                return false
            }
            let candidateFaceID = try evaluatedFaceID(
                for: entry,
                in: evaluatedDocument,
                operationName: operationName
            )
            return face(
                candidateFaceID,
                containsBoundaryEdge: edgeID,
                in: evaluatedDocument.brep
            )
        }
        guard oppositeCandidates.count == 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) symmetric mode requires exactly one opposite support face sharing the selected edge."
            )
        }
    }

    private func evaluatedEdgeID(
        for entry: TopologySummaryResult.Entry,
        in evaluatedDocument: EvaluatedDocument,
        operationName: String
    ) throws -> EdgeID {
        let persistentName = try GeneratedTopologyPersistentNameParser().parse(
            entry.persistentName,
            operationName: operationName
        )
        guard case .edge(let edgeID) = evaluatedDocument.generatedNames[persistentName] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) evaluated topology edge was not found."
            )
        }
        return edgeID
    }

    private func evaluatedFaceID(
        for entry: TopologySummaryResult.Entry,
        in evaluatedDocument: EvaluatedDocument,
        operationName: String
    ) throws -> FaceID {
        let persistentName = try GeneratedTopologyPersistentNameParser().parse(
            entry.persistentName,
            operationName: operationName
        )
        guard case .face(let faceID) = evaluatedDocument.generatedNames[persistentName] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) evaluated topology face was not found."
            )
        }
        return faceID
    }

    private func face(
        _ faceID: FaceID,
        containsBoundaryEdge edgeID: EdgeID,
        in model: BRepModel
    ) -> Bool {
        guard let face = model.faces[faceID] else {
            return false
        }
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                continue
            }
            if loop.edges.contains(where: { $0.edgeID == edgeID }) {
                return true
            }
        }
        return false
    }

    private func generatedSketchVertexOffsetTarget(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeneratedSketchVertexOffsetTarget {
        let operationName = "Generated vertex Offset Vertex"
        guard case .vertex(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a generated topology vertex target."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        let bodyFeatureID = resolvedTarget.featureID
        guard let bodyFeature = cadDocument.designGraph.nodes[bodyFeatureID],
              case let .extrude(extrude) = bodyFeature.operation,
              let profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable extrude source sketch."
            )
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently requires a normal extrude so the generated vertex can be resolved back to its source sketch plane."
            )
        }

        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target was not found in the current evaluation."
            )
        }
        guard entry.kind == .vertex,
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference a vertex on the selected body."
            )
        }
        guard let vertexPoint = entry.start else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated vertex does not expose a resolved point."
            )
        }

        let coordinate = try sketchCoordinate(from: vertexPoint, on: sketch.plane)
        let endpoint = try sketchCurveEndpoint(
            at: (x: coordinate.x, y: coordinate.y),
            in: sketch,
            operationName: operationName
        )
        let sketchSceneNodeID = try sketchSceneNodeID(
            for: extrude.profile.featureID,
            operationName: operationName
        )
        return GeneratedSketchVertexOffsetTarget(
            featureID: extrude.profile.featureID,
            target: SelectionTarget(
                sceneNodeID: sketchSceneNodeID,
                component: .sketchEntity(
                    SelectionComponentID.sketchEntity(
                        featureID: extrude.profile.featureID,
                        entityID: endpoint.entityID
                    )
                )
            ),
            handle: endpoint.handle
        )
    }

    private mutating func createSlotFromOffsetCurve(
        target: SelectionTarget,
        width: CADExpression,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode requires a selected open curve target, not a vertex handle."
            )
        }
        guard options.isSymmetric == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode already creates symmetric output and does not accept the planar symmetric option."
            )
        }
        guard options.gapFill == .round else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode closes with tangent arc caps and does not accept planar gap-fill options."
            )
        }
        guard options.supportTarget == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode does not accept an edge support target."
            )
        }
        return try createSlotSketch(
            target: target,
            width: width,
            objectRegistry: objectRegistry
        )
    }

    @discardableResult
    public mutating func offsetRegions(
        targets: [SelectionTarget],
        distance: CADExpression,
        options: OffsetCurveOptions,
        combinesRegions: Bool,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [FeatureID] {
        let distanceMeters = try resolvedLengthValue(distance, owner: "Offset Region distance")
        guard abs(distanceMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region distance must not be zero."
            )
        }
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region requires at least one selected region."
            )
        }

        let selections = try targets.map { target in
            try editableProfileRegion(
                for: target,
                operationName: "Offset Region",
                objectRegistry: objectRegistry
            )
        }

        if combinesRegions {
            guard selections.count >= 2 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Combined Offset Region requires multiple selected regions."
                )
            }
            return try appendCombinedOffsetRegions(
                selections: selections,
                distanceMeters: distanceMeters,
                options: options,
                objectRegistry: objectRegistry
            )
        }

        return try appendIndividualOffsetRegions(
            selections: selections,
            distanceMeters: distanceMeters,
            options: options,
            objectRegistry: objectRegistry
        )
    }

    private mutating func offsetProfileRegion(
        target: SelectionTarget,
        distanceMeters: Double,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        try validateOffsetRegionOptions(options, vertexHandle: vertexHandle)
        let selection = try editableProfileRegion(
            for: target,
            operationName: "Offset Region",
            objectRegistry: objectRegistry
        )
        return try appendIndividualOffsetRegions(
            selections: [selection],
            distanceMeters: distanceMeters,
            options: options,
            objectRegistry: objectRegistry
        )
    }

    private mutating func appendIndividualOffsetRegions(
        selections: [EditableProfileRegionSelection],
        distanceMeters: Double,
        options: OffsetCurveOptions,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        let plannedResults = try selections.flatMap { selection in
            let name = selection.feature.name ?? "Region"
            if options.isSymmetric {
                return [
                    (
                        name: "\(name) Offset Positive",
                        result: try buildOffsetRegion(
                            profile: selection.profile,
                            distanceMeters: distanceMeters,
                            gapFill: options.gapFill
                        )
                    ),
                    (
                        name: "\(name) Offset Negative",
                        result: try buildOffsetRegion(
                            profile: selection.profile,
                            distanceMeters: -distanceMeters,
                            gapFill: options.gapFill
                        )
                    ),
                ]
            }
            return [
                (
                    name: "\(name) Offset",
                    result: try buildOffsetRegion(
                        profile: selection.profile,
                        distanceMeters: distanceMeters,
                        gapFill: options.gapFill
                    )
                ),
            ]
        }

        return try appendOffsetRegionFeatures(
            plannedResults,
            objectRegistry: objectRegistry
        )
    }

    private mutating func appendCombinedOffsetRegions(
        selections: [EditableProfileRegionSelection],
        distanceMeters: Double,
        options: OffsetCurveOptions,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        let name = selections.first?.feature.name ?? "Regions"
        let profiles = selections.map(\.profile)
        if options.isSymmetric {
            let positiveResult = try buildCombinedOffsetRegion(
                profiles: profiles,
                distanceMeters: distanceMeters,
                gapFill: options.gapFill
            )
            let negativeResult = try buildCombinedOffsetRegion(
                profiles: profiles,
                distanceMeters: -distanceMeters,
                gapFill: options.gapFill
            )
            return try appendOffsetRegionFeatures(
                [
                    (
                        name: "\(name) Combined Offset Positive",
                        result: positiveResult
                    ),
                    (
                        name: "\(name) Combined Offset Negative",
                        result: negativeResult
                    ),
                ],
                objectRegistry: objectRegistry
            )
        }

        let result = try buildCombinedOffsetRegion(
            profiles: profiles,
            distanceMeters: distanceMeters,
            gapFill: options.gapFill
        )
        return try appendOffsetRegionFeatures(
            [
                (
                    name: "\(name) Combined Offset",
                    result: result
                ),
            ],
            objectRegistry: objectRegistry
        )
    }

    private func buildOffsetRegion(
        profile: Profile,
        distanceMeters: Double,
        gapFill: OffsetCurveGapFill
    ) throws -> OffsetRegionBuilder.Result {
        try OffsetRegionBuilder().buildOffset(
            profile: profile,
            gapFill: gapFill,
            distanceMeters: distanceMeters
        )
    }

    private func buildCombinedOffsetRegion(
        profiles: [Profile],
        distanceMeters: Double,
        gapFill: OffsetCurveGapFill
    ) throws -> OffsetRegionBuilder.Result {
        try OffsetRegionBuilder().buildCombinedOffset(
            profiles: profiles,
            gapFill: gapFill,
            distanceMeters: distanceMeters
        )
    }

    private mutating func appendOffsetRegionFeature(
        name: String,
        result: OffsetRegionBuilder.Result,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        return try appendSketchFeature(
            name: name,
            sketch: result.sketch,
            geometryRole: .sketchProfile,
            objectRegistry: objectRegistry
        )
    }

    private mutating func appendOffsetRegionFeatures(
        _ plannedResults: [PlannedOffsetRegionFeature],
        objectRegistry: ObjectTypeRegistry
    ) throws -> [FeatureID] {
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitAllFeatures = false
        defer {
            if didCommitAllFeatures == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        var featureIDs: [FeatureID] = []
        for plannedResult in plannedResults {
            let featureID = try appendOffsetRegionFeature(
                name: plannedResult.name,
                result: plannedResult.result,
                objectRegistry: objectRegistry
            )
            featureIDs.append(featureID)
        }
        didCommitAllFeatures = true
        return featureIDs
    }

    private func validateOffsetRegionOptions(
        _ options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?
    ) throws {
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Region does not accept sketch vertex handles."
            )
        }
    }

    public mutating func offsetSketchVertex(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let distanceMeters = try resolvedPositiveLengthValue(distance, owner: "Sketch vertex offset distance")
        let selection = try editableSketchEntity(for: target, operationName: "Sketch vertex offset")
        let selectedReference = try sketchPointReference(
            entityID: selection.entityID,
            entity: selection.entity,
            handle: handle,
            operationName: "Sketch vertex offset"
        )
        guard let selectedEndpoint = sketchCurveEndpoint(for: selectedReference) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch vertex offset requires a line or arc endpoint handle."
            )
        }

        let adjacentReference = try adjacentSketchCurveEndpoint(
            to: selectedReference,
            in: selection.sketch,
            owner: "Sketch vertex offset"
        )
        let adjacentEndpoint = adjacentReference.endpoint
        let adjacentEntityID = adjacentEndpoint.entityID

        try validateSketchVertexOffsetConstraints(
            selection.sketch,
            affectedEntityIDs: [selection.entityID, adjacentEntityID]
        )

        let selectedCornerID = SketchEntityID()
        let adjacentCornerID = SketchEntityID()
        let selectedSplit = try splitSketchCurve(
            selection.entity,
            targetEndpoint: selectedEndpoint,
            distance: distance,
            resolvedDistance: distanceMeters,
            owner: "Sketch vertex offset selected side"
        )
        let adjacentSplit = try splitSketchCurve(
            adjacentReference.entity,
            targetEndpoint: adjacentEndpoint,
            distance: distance,
            resolvedDistance: distanceMeters,
            owner: "Sketch vertex offset adjacent side"
        )

        var sketch = selection.sketch
        sketch.entities[selection.entityID] = selectedSplit.outer
        sketch.entities[adjacentEntityID] = adjacentSplit.outer
        sketch.entities[selectedCornerID] = selectedSplit.corner
        sketch.entities[adjacentCornerID] = adjacentSplit.corner
        sketch.constraints = offsetVertexConstraints(
            from: sketch.constraints,
            selectedReference: selectedReference,
            adjacentReference: adjacentReference.reference,
            selectedEndpoint: selectedEndpoint,
            adjacentEndpoint: adjacentEndpoint,
            selectedCornerID: selectedCornerID,
            adjacentCornerID: adjacentCornerID,
            selectedSplit: selectedSplit,
            adjacentSplit: adjacentSplit
        )
        sketch.dimensions = try dimensionsAfterSketchVertexOffset(
            sketch.dimensions,
            affectedEntityIDs: [selection.entityID, adjacentEntityID],
            selectedEndpoint: selectedEndpoint,
            adjacentEndpoint: adjacentEndpoint,
            selectedCornerID: selectedCornerID,
            adjacentCornerID: adjacentCornerID,
            selectedSplit: selectedSplit,
            adjacentSplit: adjacentSplit,
            in: sketch
        )

        var feature = selection.feature
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch vertex offset"
        )
    }

    @discardableResult
    public mutating func applySketchCornerTreatment(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget? = nil,
        distance: CADExpression,
        treatment: SketchCornerTreatment,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let resolvedDistance = try resolvedPositiveLengthValue(
            distance,
            owner: "Sketch corner treatment distance"
        )
        let selection = try editableSketchEntityBase(
            for: target,
            operationName: "Sketch corner treatment"
        )
        let corner = try sketchCornerTreatmentSelection(
            target: target,
            adjacentTarget: adjacentTarget,
            selection: selection
        )
        try validateSketchCornerTreatment(
            selection: selection,
            corner: corner
        )

        let insertedEntityID = SketchEntityID()
        let result = try sketchCornerTreatmentResult(
            corner: corner,
            distance: resolvedDistance,
            treatment: treatment,
            insertedEntityID: insertedEntityID
        )

        var sketch = selection.sketch
        sketch.entities[corner.selectedEndpoint.entityID] = result.selectedEntity
        sketch.entities[corner.adjacentEndpoint.entityID] = result.adjacentEntity
        sketch.entities[insertedEntityID] = result.insertedEntity
        sketch.constraints = constraintsAfterSketchCornerTreatment(
            sketch.constraints,
            corner: corner,
            result: result
        )
        sketch.dimensions = try dimensionsAfterSketchCornerTreatment(
            sketch.dimensions,
            affectedEntityIDs: [
                corner.selectedEndpoint.entityID,
                corner.adjacentEndpoint.entityID,
            ],
            in: sketch
        )

        var feature = selection.feature
        try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch corner treatment"
        )
        return insertedEntityID
    }

    public mutating func offsetBodyFace(
        target: SelectionTarget,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let offsetMeters = try resolvedLengthValue(distance, owner: "Face offset distance")
        guard abs(offsetMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset distance must not be zero."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: "Face offset"
        )
        let face = try editableBodyFace(
            for: resolvedTarget.target,
            objectRegistry: objectRegistry
        )
        let featureID = resolvedTarget.featureID
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case var .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires an editable extrude body."
            )
        }
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case var .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires an editable sketch profile."
            )
        }
        if let circleEntry = singleCircleEntry(in: sketch) {
            try offsetCylinderFace(
                face: face,
                offsetMeters: offsetMeters,
                circleEntry: circleEntry,
                sketch: &sketch,
                profileFeature: &profileFeature,
                feature: &feature,
                extrude: &extrude,
                featureID: featureID,
                sceneNodeID: resolvedTarget.sceneNodeID,
                objectRegistry: objectRegistry
            )
            return
        }
        guard isRectangleProfile(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires an editable rectangle or circle profile."
            )
        }
        guard var bounds = try resolvedSketchBounds2D(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset requires a finite rectangle profile."
            )
        }

        var translationYDelta = 0.0
        var updatesProfile = false
        switch face {
        case .left:
            bounds.minX -= offsetMeters
            updatesProfile = true
        case .right:
            bounds.maxX += offsetMeters
            updatesProfile = true
        case .top:
            bounds.maxY += offsetMeters
            updatesProfile = true
        case .bottom:
            bounds.minY -= offsetMeters
            updatesProfile = true
        case .back, .front:
            let nextDepth = try offsetExtrudeDepth(
                extrude: &extrude,
                face: face,
                offsetMeters: offsetMeters
            )
            if face == .front {
                translationYDelta = -offsetMeters
            }
            extrude.distance = .length(nextDepth, .meter)
            feature.operation = .extrude(extrude)
        case .side:
            throw EditorError(
                code: .commandInvalid,
                message: "Rectangle face offset does not support side faces."
            )
        }

        if updatesProfile {
            guard bounds.maxX - bounds.minX > 1.0e-9,
                  bounds.maxY - bounds.minY > 1.0e-9 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Face offset would collapse the rectangle profile."
                )
            }

            let firstCorner = SketchPoint(
                x: .length(bounds.minX, .meter),
                y: .length(bounds.minY, .meter)
            )
            let oppositeCorner = SketchPoint(
                x: .length(bounds.maxX, .meter),
                y: .length(bounds.maxY, .meter)
            )
            try updateRectangleSketch(
                &sketch,
                firstCorner: firstCorner,
                oppositeCorner: oppositeCorner
            )
            profileFeature.operation = .sketch(sketch)
        }

        var updatedCADDocument = cadDocument
        do {
            if updatesProfile {
                try updatedCADDocument.replaceFeatures([profileFeature, feature])
            } else {
                try updatedCADDocument.replaceFeature(feature)
            }
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        if abs(translationYDelta) > 0.0 {
            try translateSceneNode(resolvedTarget.sceneNodeID, y: translationYDelta)
        }
        try synchronizeObjectPropertiesFromSource(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func chamferBodyEdges(
        targets: [SelectionTarget],
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let chamferMeters = try resolvedPositiveLengthValue(distance, owner: "Edge chamfer distance")
        guard !targets.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer requires at least one edge selection target."
            )
        }

        let resolvedTargets = try targets.map { target in
            try editableBodyTargetResolution(
                for: target,
                operationName: "Edge chamfer"
            )
        }
        var sceneNodeID: SceneNodeID?
        for target in resolvedTargets.map(\.target) {
            if let resolvedSceneNodeID = sceneNodeID {
                guard resolvedSceneNodeID == target.sceneNodeID else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Edge chamfer currently requires all edge targets to belong to the same body."
                    )
                }
            } else {
                sceneNodeID = target.sceneNodeID
            }
        }

        guard let resolvedSceneNodeID = sceneNodeID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer requires an editable body edge."
            )
        }
        guard let featureID = resolvedTargets.first?.featureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer requires an editable body edge."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge chamfer requires an editable extrude body."
            )
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge chamfer currently requires a normal extrude."
            )
        }
        _ = try resolvedPositiveLengthValue(extrude.distance, owner: "Extrude distance")
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge chamfer requires an editable sketch profile."
            )
        }

        let profileLoop = try EditableExtrudeProfileLoop.editableLoop(
            in: sketch,
            document: self,
            operationName: "Edge chamfer"
        )
        let targetIndices: Set<Int>
        if let bounds = try resolvedSketchBounds2D(sketch),
           try rectangleLineIDs(in: sketch) != nil {
            targetIndices = try rectangleProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                bounds: bounds,
                operationName: "Edge chamfer",
                objectRegistry: objectRegistry
            )
        } else {
            targetIndices = try generatedProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                sketchPlane: sketch.plane,
                expectedKind: .edge,
                operationName: "Edge chamfer",
                objectRegistry: objectRegistry
            )
        }
        let nextSketch = try profileLoop.chamferedSketch(
            targetVertexIndices: targetIndices,
            distance: chamferMeters,
            operationName: "Edge chamfer"
        )
        profileFeature.operation = .sketch(nextSketch)
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
            try validateEditableBodyCandidate(
                updatedCADDocument,
                operationName: "Edge chamfer",
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge chamfer produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try markBodyObjectAsSourceEditedSolid(featureID: featureID)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func filletBodyEdges(
        targets: [SelectionTarget],
        radius: CADExpression,
        segmentCount: Int,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let filletMeters = try resolvedPositiveLengthValue(radius, owner: "Edge fillet radius")
        guard (3 ... 64).contains(segmentCount) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet segment count must be between 3 and 64."
            )
        }
        guard !targets.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet requires at least one edge selection target."
            )
        }

        let resolvedTargets = try targets.map { target in
            try editableBodyTargetResolution(
                for: target,
                operationName: "Edge fillet"
            )
        }
        var sceneNodeID: SceneNodeID?
        for target in resolvedTargets.map(\.target) {
            if let resolvedSceneNodeID = sceneNodeID {
                guard resolvedSceneNodeID == target.sceneNodeID else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Edge fillet currently requires all edge targets to belong to the same body."
                    )
                }
            } else {
                sceneNodeID = target.sceneNodeID
            }
        }

        guard let resolvedSceneNodeID = sceneNodeID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet requires an editable body edge."
            )
        }
        guard let featureID = resolvedTargets.first?.featureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet requires an editable body edge."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge fillet requires an editable extrude body."
            )
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Edge fillet currently requires a normal extrude."
            )
        }
        _ = try resolvedPositiveLengthValue(extrude.distance, owner: "Extrude distance")
        guard var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge fillet requires an editable sketch profile."
            )
        }

        let profileLoop = try EditableExtrudeProfileLoop.editableLoop(
            in: sketch,
            document: self,
            operationName: "Edge fillet"
        )
        let targetIndices: Set<Int>
        if let bounds = try resolvedSketchBounds2D(sketch),
           try rectangleLineIDs(in: sketch) != nil {
            targetIndices = try rectangleProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                bounds: bounds,
                operationName: "Edge fillet",
                objectRegistry: objectRegistry
            )
        } else {
            targetIndices = try generatedProfileLoopVertexIndices(
                for: resolvedTargets.map(\.target),
                profileLoop: profileLoop,
                sketchPlane: sketch.plane,
                expectedKind: .edge,
                operationName: "Edge fillet",
                objectRegistry: objectRegistry
            )
        }
        let nextSketch = try profileLoop.filletedSketch(
            targetVertexIndices: targetIndices,
            radius: filletMeters,
            operationName: "Edge fillet"
        )
        profileFeature.operation = .sketch(nextSketch)
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
            try validateEditableBodyCandidate(
                updatedCADDocument,
                operationName: "Edge fillet",
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Edge fillet produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try markBodyObjectAsSourceEditedSolid(
            featureID: featureID,
            profileArcSegmentCount: segmentCount
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func moveBodyVertex(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Vertex move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Vertex move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Vertex move delta must not be zero."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: "Vertex move"
        )
        let featureID = resolvedTarget.featureID
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation,
              var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Vertex move requires an editable sketch profile."
            )
        }

        let nextSketch: Sketch
        let preservesObjectProperties: Bool
        if isRectangleProfile(sketch) {
            let vertex = try editableBodyVertex(
                for: resolvedTarget.target,
                objectRegistry: objectRegistry
            )
            guard var bounds = try resolvedSketchBounds2D(sketch) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Vertex move requires a finite rectangle profile."
                )
            }

            switch vertex {
            case .bottomLeft:
                bounds.minX += deltaXMeters
                bounds.minY += deltaYMeters
            case .bottomRight:
                bounds.maxX += deltaXMeters
                bounds.minY += deltaYMeters
            case .topRight:
                bounds.maxX += deltaXMeters
                bounds.maxY += deltaYMeters
            case .topLeft:
                bounds.minX += deltaXMeters
                bounds.maxY += deltaYMeters
            }

            guard bounds.maxX - bounds.minX > 1.0e-9,
                  bounds.maxY - bounds.minY > 1.0e-9 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Vertex move would collapse the rectangle profile."
                )
            }

            var rectangleSketch = sketch
            try updateRectangleSketch(
                &rectangleSketch,
                firstCorner: sketchPoint(x: bounds.minX, y: bounds.minY),
                oppositeCorner: sketchPoint(x: bounds.maxX, y: bounds.maxY)
            )
            nextSketch = rectangleSketch
            preservesObjectProperties = true
        } else {
            let profileLoop = try EditableExtrudeProfileLoop.editableLoop(
                in: sketch,
                document: self,
                operationName: "Vertex move"
            )
            let index = try profileLoopVertexIndex(
                for: resolvedTarget.target,
                profileLoop: profileLoop,
                sketchPlane: sketch.plane,
                expectedKind: .vertex,
                operationName: "Vertex move",
                objectRegistry: objectRegistry
            )
            nextSketch = try profileLoop.movedVertexSketch(
                targetVertexIndex: index,
                deltaX: deltaXMeters,
                deltaY: deltaYMeters,
                operationName: "Vertex move"
            )
            preservesObjectProperties = false
        }

        profileFeature.operation = .sketch(nextSketch)
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures([profileFeature, feature])
            try validateEditableBodyCandidate(
                updatedCADDocument,
                operationName: "Vertex move",
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Vertex move produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        if preservesObjectProperties {
            try synchronizeObjectPropertiesFromSource(
                featureID: featureID,
                objectRegistry: objectRegistry
            )
        } else {
            try markBodyObjectAsSourceEditedSolid(featureID: featureID)
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    public mutating func moveSketchEntityPoint(
        target: SelectionTarget,
        handle: SketchEntityPointHandle,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Sketch point move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Sketch point move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch point move delta must not be zero."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch point move")
        var feature = selection.feature
        var sketch = selection.sketch
        let movedReference = try sketchPointReference(
            entityID: selection.entityID,
            entity: selection.entity,
            handle: handle,
            operationName: "Sketch point move"
        )
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        try pointPropagator.validateCanMove(
            movedReference,
            in: sketch,
            owner: "Sketch point move"
        )
        let updatedEntity: SketchEntity
        switch selection.entity {
        case .point(let point):
            guard handle == .point else {
                throw incompatibleSketchPointHandle(handle, entityKind: "point", operationName: "Sketch point move")
            }
            let movedPoint = translatedSketchPoint(
                point,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaXMeters: deltaXMeters,
                deltaYMeters: deltaYMeters
            )
            _ = try resolvedLengthValue(movedPoint.x, owner: "Sketch point x")
            _ = try resolvedLengthValue(movedPoint.y, owner: "Sketch point y")
            updatedEntity = .point(movedPoint)
        case .line(var line):
            switch handle {
            case .lineStart:
                line.start = translatedSketchPoint(
                    line.start,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters
                )
            case .lineEnd:
                line.end = translatedSketchPoint(
                    line.end,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters
                )
            case .point, .circleCenter, .arcCenter, .arcStart, .arcEnd:
                throw incompatibleSketchPointHandle(handle, entityKind: "line", operationName: "Sketch point move")
            }
            _ = try resolvedLineMetrics(line, owner: "Sketch line")
            updatedEntity = .line(line)
        case .circle(var circle):
            guard handle == .circleCenter else {
                throw incompatibleSketchPointHandle(handle, entityKind: "circle", operationName: "Sketch point move")
            }
            circle.center = translatedSketchPoint(
                circle.center,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaXMeters: deltaXMeters,
                deltaYMeters: deltaYMeters
            )
            _ = try resolvedLengthValue(circle.center.x, owner: "Sketch circle center x")
            _ = try resolvedLengthValue(circle.center.y, owner: "Sketch circle center y")
            _ = try resolvedPositiveLengthValue(circle.radius, owner: "Sketch circle radius")
            updatedEntity = .circle(circle)
        case .arc(var arc):
            switch handle {
            case .arcCenter:
                arc.center = translatedSketchPoint(
                    arc.center,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters
                )
            case .arcStart:
                arc.startAngle = try movedArcEndpointAngle(
                    arc,
                    endpointAngle: arc.startAngle,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters,
                    owner: "Sketch arc start move"
                )
            case .arcEnd:
                arc.endAngle = try movedArcEndpointAngle(
                    arc,
                    endpointAngle: arc.endAngle,
                    deltaXMeters: deltaXMeters,
                    deltaYMeters: deltaYMeters,
                    owner: "Sketch arc end move"
                )
            case .point, .lineStart, .lineEnd, .circleCenter:
                throw incompatibleSketchPointHandle(handle, entityKind: "arc", operationName: "Sketch point move")
            }
            try validateArc(arc, owner: "Sketch arc")
            updatedEntity = .arc(arc)
        case .spline:
            throw incompatibleSketchPointHandle(handle, entityKind: "spline", operationName: "Sketch point move")
        }

        sketch.entities[selection.entityID] = updatedEntity
        try pointPropagator.propagate(
            from: movedReference,
            in: &sketch,
            owner: "Sketch point move"
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch point move"
        )
    }

    private func negatedExpression(_ expression: CADExpression) -> CADExpression {
        .multiply(expression, .constant(.scalar(-1.0)))
    }

    public mutating func moveSketchSplineControlPoint(
        target: SelectionTarget,
        controlPointIndex: Int,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Sketch spline control point move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Sketch spline control point move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point move delta must not be zero."
            )
        }
        guard controlPointIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point index must not be negative."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch spline control point move")
        guard case .spline(var spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point move requires a spline entity."
            )
        }
        guard spline.controlPoints.indices.contains(controlPointIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch spline control point move requires an existing control point."
            )
        }
        let movedReference = SketchReference.splineControlPoint(
            entity: selection.entityID,
            index: controlPointIndex
        )
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        try pointPropagator.validateCanMove(
            movedReference,
            in: selection.sketch,
            owner: "Sketch spline control point move"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        spline.controlPoints[controlPointIndex] = translatedSketchPoint(
            spline.controlPoints[controlPointIndex],
            deltaX: deltaX,
            deltaY: deltaY,
            deltaXMeters: deltaXMeters,
            deltaYMeters: deltaYMeters
        )
        try validateSpline(spline, owner: "Sketch spline")
        sketch.entities[selection.entityID] = .spline(spline)
        try pointPropagator.propagate(
            from: movedReference,
            in: &sketch,
            owner: "Sketch spline control point move"
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch spline control point move"
        )
    }

    public mutating func slideSketchSplineControlPoints(
        target: SelectionTarget,
        controlPointIndexes: [Int],
        direction: SplineControlPointSlideDirection,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let distanceMeters = try resolvedLengthValue(distance, owner: "Sketch spline control point slide distance")
        guard abs(distanceMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide distance must not be zero."
            )
        }
        guard controlPointIndexes.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide requires at least one control point index."
            )
        }
        guard controlPointIndexes.allSatisfy({ $0 >= 0 }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point indexes must not contain negative values."
            )
        }
        guard Set(controlPointIndexes).count == controlPointIndexes.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide requires unique control point indexes."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch spline control point slide")
        guard case .spline(var spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point slide requires a spline entity."
            )
        }
        guard controlPointIndexes.allSatisfy({ spline.controlPoints.indices.contains($0) }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch spline control point slide requires existing control points."
            )
        }
        let slideDirections = try controlPointIndexes.map { index in
            try splineControlPointSlideDirection(
                in: spline,
                controlPointIndex: index,
                direction: direction,
                owner: "Sketch spline control point slide"
            )
        }
        let movedReferences = controlPointIndexes.map { index in
            SketchReference.splineControlPoint(
                entity: selection.entityID,
                index: index
            )
        }
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        for reference in movedReferences {
            try pointPropagator.validateCanMove(
                reference,
                in: selection.sketch,
                owner: "Sketch spline control point slide"
            )
        }

        var feature = selection.feature
        var sketch = selection.sketch
        for (index, slideDirection) in zip(controlPointIndexes, slideDirections) {
            spline.controlPoints[index] = translatedSketchPoint(
                spline.controlPoints[index],
                directionX: slideDirection.x,
                directionY: slideDirection.y,
                distance: distance
            )
        }
        try validateSpline(spline, owner: "Sketch spline")
        sketch.entities[selection.entityID] = .spline(spline)
        for reference in movedReferences {
            try pointPropagator.propagate(
                from: reference,
                in: &sketch,
                owner: "Sketch spline control point slide"
            )
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch spline control point slide"
        )
    }

    @discardableResult
    public mutating func insertSketchSplineControlPoint(
        target: SelectionTarget,
        fraction: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> Int {
        let resolvedFraction = try resolvedScalarValue(
            fraction,
            owner: "Sketch spline control point insertion fraction"
        )
        guard resolvedFraction > ModelingTolerance.standard.distance,
              resolvedFraction < 1.0 - ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion fraction must be greater than zero and less than one."
            )
        }

        let selection = try editableSketchEntity(
            for: target,
            operationName: "Sketch spline control point insertion"
        )
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion requires a spline entity."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion requires an open spline curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch spline control point insertion cannot edit a generated Bridge Curve source."
            )
        }

        let insertion = try insertedSplineControlPoint(
            in: spline,
            fraction: resolvedFraction,
            owner: "Sketch spline control point insertion"
        )
        let constraints = try constraintsAfterSketchSplineControlPointInsertion(
            selection.sketch.constraints,
            entityID: selection.entityID,
            insertion: insertion
        )
        let dimensions = try dimensionsAfterSketchSplineControlPointInsertion(
            selection.sketch.dimensions,
            entityID: selection.entityID,
            insertion: insertion
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .spline(insertion.spline)
        sketch.constraints = constraints
        sketch.dimensions = dimensions

        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch spline control point insertion"
        )
        return insertion.insertedControlPointIndex
    }

    public mutating func setSketchCircleParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard center != nil || radius != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch circle parameter update requires a center or radius value."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch circle parameter update")
        guard case var .circle(circle) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch circle parameter update requires a circle entity target."
            )
        }
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        if center != nil {
            try pointPropagator.validateCanMove(
                .circleCenter(selection.entityID),
                in: selection.sketch,
                owner: "Sketch circle parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.validateCanResizeCircularEntity(
                selection.entityID,
                in: selection.sketch,
                owner: "Sketch circle parameter update"
            )
        }
        if let center {
            _ = try resolvedLengthValue(center.x, owner: "Sketch circle center x")
            _ = try resolvedLengthValue(center.y, owner: "Sketch circle center y")
            circle.center = center
        }
        if let radius {
            _ = try resolvedPositiveLengthValue(radius, owner: "Sketch circle radius")
            circle.radius = radius
        } else {
            _ = try resolvedPositiveLengthValue(circle.radius, owner: "Sketch circle radius")
        }

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .circle(circle)
        if center != nil {
            try pointPropagator.propagate(
                from: .circleCenter(selection.entityID),
                in: &sketch,
                owner: "Sketch circle parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.propagateCircularRadius(
                from: selection.entityID,
                in: &sketch,
                owner: "Sketch circle parameter update"
            )
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch circle parameter update"
        )
    }

    public mutating func setSketchArcParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?,
        startAngle: CADExpression?,
        endAngle: CADExpression?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard center != nil || radius != nil || startAngle != nil || endAngle != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch arc parameter update requires at least one value."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch arc parameter update")
        guard case var .arc(arc) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch arc parameter update requires an arc entity target."
            )
        }
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        if center != nil {
            try pointPropagator.validateCanMove(
                .arcCenter(selection.entityID),
                in: selection.sketch,
                owner: "Sketch arc parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.validateCanResizeCircularEntity(
                selection.entityID,
                in: selection.sketch,
                owner: "Sketch arc parameter update"
            )
        }
        if let center {
            _ = try resolvedLengthValue(center.x, owner: "Sketch arc center x")
            _ = try resolvedLengthValue(center.y, owner: "Sketch arc center y")
            arc.center = center
        }
        if let radius {
            _ = try resolvedPositiveLengthValue(radius, owner: "Sketch arc radius")
            arc.radius = radius
        }
        if let startAngle {
            _ = try resolvedAngleValue(startAngle, owner: "Sketch arc start angle")
            arc.startAngle = startAngle
        }
        if let endAngle {
            _ = try resolvedAngleValue(endAngle, owner: "Sketch arc end angle")
            arc.endAngle = endAngle
        }
        try validateArc(arc, owner: "Sketch arc")

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .arc(arc)
        if center != nil {
            try pointPropagator.propagate(
                from: .arcCenter(selection.entityID),
                in: &sketch,
                owner: "Sketch arc parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.propagateCircularRadius(
                from: selection.entityID,
                in: &sketch,
                owner: "Sketch arc parameter update"
            )
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch arc parameter update"
        )
    }

    public mutating func setSketchEntityDimension(
        target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedValue = try resolvedSketchEntityDimensionValue(
            value,
            kind: kind,
            owner: "Sketch entity dimension"
        )
        let selection = try editableSketchEntity(for: target, operationName: "Sketch entity dimension update")
        try validateResolvedSketchEntityDimensionValue(
            resolvedValue,
            kind: kind,
            entity: selection.entity
        )
        var feature = selection.feature
        var sketch = selection.sketch
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        switch selection.entity {
        case .line(let line):
            guard kind == .length || kind == .angle else {
                throw incompatibleSketchDimension(kind, entityKind: "line")
            }
            if kind == .length,
               let axis = try rectangleSideDimensionAxis(
                in: sketch,
                entityID: selection.entityID
            ) {
                try updateRectangleSketchForSideDimension(
                    &sketch,
                    axis: axis,
                    length: value,
                    resolvedLength: resolvedValue
                )
            } else {
                let startReference = SketchReference.lineStart(selection.entityID)
                let endReference = SketchReference.lineEnd(selection.entityID)
                let startAnchored = pointPropagator.isAnchored(startReference, in: sketch)
                let endAnchored = pointPropagator.isAnchored(endReference, in: sketch)
                let metrics = try resolvedLineMetrics(line, owner: "Sketch line dimension update")
                if kind == .angle {
                    try validateLineAngleDimensionAgainstDirectOrientationConstraints(
                        resolvedValue,
                        lineID: selection.entityID,
                        sketch: sketch,
                        owner: "Sketch line dimension update"
                    )
                }
                let isConflictingFixedDimension: Bool
                switch kind {
                case .length:
                    isConflictingFixedDimension = abs(metrics.length - resolvedValue) > 1.0e-12
                case .angle:
                    isConflictingFixedDimension = angularDistance(metrics.angleRadians, resolvedValue) > 1.0e-12
                case .radius, .diameter:
                    isConflictingFixedDimension = true
                }
                guard startAnchored == false || endAnchored == false || isConflictingFixedDimension == false else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch line dimension update cannot change a line with both endpoints fixed."
                    )
                }
                let movedReference: SketchReference?
                if startAnchored && endAnchored {
                    movedReference = nil
                } else if endAnchored && startAnchored == false {
                    let nextLine: SketchLine
                    switch kind {
                    case .length:
                        nextLine = try resizedLinePreservingEnd(
                            line,
                            length: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .angle:
                        nextLine = try angledLinePreservingEnd(
                            line,
                            angleRadians: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .radius, .diameter:
                        throw incompatibleSketchDimension(kind, entityKind: "line")
                    }
                    sketch.entities[selection.entityID] = .line(nextLine)
                    movedReference = startReference
                } else {
                    let nextLine: SketchLine
                    switch kind {
                    case .length:
                        nextLine = try resizedLine(
                            line,
                            length: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .angle:
                        nextLine = try angledLinePreservingStart(
                            line,
                            angleRadians: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .radius, .diameter:
                        throw incompatibleSketchDimension(kind, entityKind: "line")
                    }
                    sketch.entities[selection.entityID] = .line(nextLine)
                    movedReference = endReference
                }
                if let movedReference {
                    try pointPropagator.propagate(
                        from: movedReference,
                        in: &sketch,
                        owner: "Sketch line dimension update"
                    )
                }
            }
        case .circle(var circle):
            guard kind == .radius || kind == .diameter else {
                throw incompatibleSketchDimension(kind, entityKind: "circle")
            }
            try pointPropagator.validateCanResizeCircularEntity(
                selection.entityID,
                in: sketch,
                owner: "Sketch entity dimension update"
            )
            circle.radius = try radiusExpression(for: kind, value: value)
            sketch.entities[selection.entityID] = .circle(circle)
            try pointPropagator.propagateCircularRadius(
                from: selection.entityID,
                in: &sketch,
                owner: "Sketch entity dimension update"
            )
        case .arc(var arc):
            guard kind == .radius || kind == .diameter || kind == .angle else {
                throw incompatibleSketchDimension(kind, entityKind: "arc")
            }
            if kind == .angle {
                let startReference = SketchReference.arcStart(selection.entityID)
                let endReference = SketchReference.arcEnd(selection.entityID)
                let startAnchored = pointPropagator.isAnchored(startReference, in: sketch)
                let endAnchored = pointPropagator.isAnchored(endReference, in: sketch)
                let startAngle = try resolvedAngleValue(
                    arc.startAngle,
                    owner: "Sketch entity dimension update start angle"
                )
                let endAngle = try resolvedAngleValue(
                    arc.endAngle,
                    owner: "Sketch entity dimension update end angle"
                )
                let currentSpan = try normalizedPartialArcSpan(
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                guard startAnchored == false || endAnchored == false || abs(currentSpan - resolvedValue) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch arc span dimension update cannot change an arc with both endpoints fixed."
                    )
                }
                let movedReference: SketchReference?
                if startAnchored && endAnchored {
                    movedReference = nil
                } else if endAnchored && startAnchored == false {
                    arc.startAngle = .angle(endAngle - resolvedValue, .radian)
                    movedReference = startReference
                } else {
                    arc.endAngle = .angle(startAngle + resolvedValue, .radian)
                    movedReference = endReference
                }
                try validateArc(arc, owner: "Sketch entity dimension update")
                sketch.entities[selection.entityID] = .arc(arc)
                if let movedReference {
                    try pointPropagator.propagate(
                        from: movedReference,
                        in: &sketch,
                        owner: "Sketch entity dimension update"
                    )
                }
            } else {
                try pointPropagator.validateCanResizeCircularEntity(
                    selection.entityID,
                    in: sketch,
                    owner: "Sketch entity dimension update"
                )
                arc.radius = try radiusExpression(for: kind, value: value)
                sketch.entities[selection.entityID] = .arc(arc)
            }
            if kind != .angle {
                try pointPropagator.propagateCircularRadius(
                    from: selection.entityID,
                    in: &sketch,
                    owner: "Sketch entity dimension update"
                )
            }
        case .point:
            throw incompatibleSketchDimension(kind, entityKind: "point")
        case .spline:
            throw incompatibleSketchDimension(kind, entityKind: "spline")
        }
        sketch.dimensions = dimensionsAfterSettingEntityDimension(
            sketch.dimensions,
            entityID: selection.entityID,
            entity: selection.entity,
            kind: kind,
            value: value
        )

        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch entity dimension update"
        )
    }

    public mutating func convertSketchLineToArc(
        target: SelectionTarget,
        sagitta: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedSagitta = try resolvedLengthValue(sagitta, owner: "Sketch line arc sagitta")
        guard abs(resolvedSagitta) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line arc sagitta must not be zero."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch line arc conversion")
        guard case let .line(line) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line arc conversion requires a line entity target."
            )
        }
        let arc = try convertedArc(
            from: line,
            sagitta: resolvedSagitta,
            owner: "Sketch line arc conversion"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .arc(arc)
        sketch.constraints = constraintsAfterLineToArcConversion(
            sketch.constraints,
            entityID: selection.entityID
        )
        sketch.dimensions = dimensionsAfterLineToArcConversion(
            sketch.dimensions,
            entityID: selection.entityID
        )

        if sketch.entities.count == 1 {
            try setSketchObjectType(
                featureID: selection.featureID,
                typeID: .arc,
                objectRegistry: objectRegistry
            )
        } else {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch line arc conversion"
        )
    }

    public mutating func convertSketchLineToSpline(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch line spline conversion")
        guard case let .line(line) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line spline conversion requires a line entity target."
            )
        }
        try validateLineCanConvertToSpline(
            entityID: selection.entityID,
            sketch: selection.sketch,
            owner: "Sketch line spline conversion"
        )
        let spline = try convertedSpline(
            from: line,
            owner: "Sketch line spline conversion"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .spline(spline)
        sketch.constraints = try constraintsAfterLineToSplineConversion(
            sketch.constraints,
            entityID: selection.entityID,
            originalSketch: selection.sketch,
            owner: "Sketch line spline conversion"
        )
        sketch.dimensions = dimensionsAfterLineToSplineConversion(
            sketch.dimensions,
            entityID: selection.entityID
        )

        if sketch.entities.count == 1 {
            try setSketchObjectType(
                featureID: selection.featureID,
                typeID: .spline,
                objectRegistry: objectRegistry
            )
        } else {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch line spline conversion"
        )
    }

    public mutating func reverseSketchCurve(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve reverse")
        let reversedEntity: SketchEntity
        let splineControlPointCount: Int?
        switch selection.entity {
        case .line(let line):
            let reversedLine = SketchLine(start: line.end, end: line.start)
            _ = try resolvedLineMetrics(reversedLine, owner: "Sketch curve reverse")
            reversedEntity = .line(reversedLine)
            splineControlPointCount = nil
        case .spline(var spline):
            spline.controlPoints = Array(spline.controlPoints.reversed())
            try validateSpline(spline, owner: "Sketch curve reverse")
            reversedEntity = .spline(spline)
            splineControlPointCount = spline.controlPoints.count
        case .arc:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse cannot reverse arc direction until arc source direction is represented."
            )
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse requires an open line or spline curve; circles do not expose direction."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse requires a line or spline curve target."
            )
        }

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = reversedEntity
        sketch.constraints = constraintsAfterSketchCurveReverse(
            sketch.constraints,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )
        sketch.dimensions = dimensionsAfterSketchCurveReverse(
            sketch.dimensions,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitReverse = false
        defer {
            if didCommitReverse == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources = bridgeCurveSourcesAfterSketchCurveReverse(
            productMetadata.bridgeCurveSources,
            featureID: selection.featureID,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve reverse"
        )
        didCommitReverse = true
    }

    public mutating func rebuildSketchCurve(
        target: SelectionTarget,
        options: CurveRebuildOptions,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> CurveRebuildReport {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve rebuild")
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild currently requires a spline entity target."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild currently requires an open spline curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild cannot edit a generated Bridge Curve source."
            )
        }

        let rebuilt: RebuiltSketchSpline
        switch options.method {
        case .points(let controlPointCount):
            rebuilt = try rebuiltSketchSplineByPointCount(
                spline,
                controlPointCount: controlPointCount,
                owner: "Sketch curve rebuild"
            )
        case .refit(let tolerance, let keepsCorners):
            rebuilt = try rebuiltSketchSplineByRefit(
                spline,
                tolerance: tolerance,
                keepsCorners: keepsCorners,
                owner: "Sketch curve rebuild"
            )
        case .explicitControl(let degree, let spanCount, let weight):
            rebuilt = try rebuiltSketchSplineByExplicitControl(
                spline,
                degree: degree,
                spanCount: spanCount,
                weight: weight,
                owner: "Sketch curve rebuild"
            )
        }

        let constraints = try constraintsAfterSketchCurveRebuild(
            selection.sketch.constraints,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )
        let dimensions = try dimensionsAfterSketchCurveRebuild(
            selection.sketch.dimensions,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )
        let bridgeCurveSources = try bridgeCurveSourcesAfterSketchCurveRebuild(
            productMetadata.bridgeCurveSources,
            featureID: selection.featureID,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .spline(rebuilt.spline)
        sketch.constraints = constraints
        sketch.dimensions = dimensions

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitRebuild = false
        defer {
            if didCommitRebuild == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources = bridgeCurveSources
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve rebuild"
        )
        didCommitRebuild = true
        return CurveRebuildReport(
            sourceFeatureID: selection.featureID.description,
            entityID: selection.entityID.description,
            method: curveRebuildReportMethod(for: options),
            originalControlPointCount: rebuilt.originalControlPointCount,
            rebuiltControlPointCount: rebuilt.rebuiltControlPointCount,
            originalSpanCount: rebuilt.originalSegmentCount,
            rebuiltSpanCount: rebuilt.rebuiltSegmentCount,
            deviationMeasurement: .analyticCubicBezier,
            maximumDeviationMeters: rebuilt.deviation.maximumDistance,
            rootMeanSquareDeviationMeters: rebuilt.deviation.rootMeanSquareDistance,
            maximumDeviationFraction: rebuilt.deviation.maximumDistanceFraction,
            evaluatedIntervalCount: rebuilt.deviation.evaluatedIntervalCount,
            criticalPointCount: rebuilt.deviation.criticalPointCount
        )
    }

    public mutating func extendSketchCurve(
        target: SelectionTarget,
        distance: CADExpression,
        shape: ExtendCurveShape = .natural,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedDistance = try resolvedPositiveLengthValue(
            distance,
            owner: "Sketch curve extend distance"
        )
        let selection = try editableSketchEntityBase(
            for: target,
            operationName: "Sketch curve extend"
        )
        let endpoint = try extendCurveEndpoint(
            for: target,
            selection: selection,
            operationName: "Sketch curve extend"
        )
        try validateSketchCurveCanExtend(
            selection: selection,
            endpoint: endpoint,
            shape: shape
        )
        let extendedEntity = try extendedSketchCurveEntity(
            selection.entity,
            endpoint: endpoint,
            distance: distance,
            resolvedDistance: resolvedDistance,
            shape: shape,
            owner: "Sketch curve extend"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = extendedEntity

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitExtend = false
        defer {
            if didCommitExtend == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve extend"
        )
        didCommitExtend = true
    }

    @discardableResult
    public mutating func splitSketchCurve(
        target: SelectionTarget,
        fraction: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let resolvedFraction = try resolvedScalarValue(fraction, owner: "Sketch curve split fraction")
        guard resolvedFraction > ModelingTolerance.standard.distance,
              resolvedFraction < 1.0 - ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split fraction must be greater than zero and less than one."
            )
        }
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve split")
        try validateSketchCurveCanSplit(selection: selection)

        let newEntityID = SketchEntityID()
        let split = try splitSketchCurveEntity(
            selection.entity,
            entityID: selection.entityID,
            newEntityID: newEntityID,
            fraction: resolvedFraction,
            owner: "Sketch curve split"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = split.retainedEntity
        sketch.entities[newEntityID] = split.newEntity
        sketch.constraints = constraintsAfterSketchCurveSplit(
            sketch.constraints,
            split: split
        )
        sketch.dimensions = dimensionsAfterSketchCurveSplit(
            sketch.dimensions,
            split: split
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSplit = false
        defer {
            if didCommitSplit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        productMetadata.bridgeCurveSources = try bridgeCurveSourcesAfterSketchCurveSplit(
            productMetadata.bridgeCurveSources,
            split: split
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve split"
        )
        didCommitSplit = true
        return newEntityID
    }

    public mutating func trimSketchCurveSegment(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve trim")
        try validateSketchCurveSegmentCanTrim(selection: selection)

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities.removeValue(forKey: selection.entityID)
        sketch.constraints = constraintsAfterSketchCurveTrim(
            sketch.constraints,
            trimmedEntityID: selection.entityID
        )
        sketch.dimensions = dimensionsAfterSketchCurveTrim(
            sketch.dimensions,
            trimmedEntityID: selection.entityID
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitTrim = false
        defer {
            if didCommitTrim == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve trim"
        )
        didCommitTrim = true
    }

    @discardableResult
    public mutating func cutSketchCurve(
        target: SelectionTarget,
        cutter: SelectionTarget,
        options: CutCurveOptions = CutCurveOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SketchEntityID] {
        let targetSelection = try editableSketchEntity(for: target, operationName: "Cut Curve target")
        let cutterSelection = try editableSketchEntity(for: cutter, operationName: "Cut Curve cutter")
        if case .circle = targetSelection.entity {
            return try cutSketchCircleTarget(
                targetSelection: targetSelection,
                cutterSelection: cutterSelection,
                options: options,
                objectRegistry: objectRegistry
            )
        }
        let fractions = try cutSketchCurveFractions(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        var createdEntityIDs: [SketchEntityID] = []
        var remainingTarget = target
        var previousFraction = 0.0
        for fraction in fractions {
            let denominator = 1.0 - previousFraction
            guard denominator > 1.0e-12 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve intersection sequence collapsed the remaining target segment."
                )
            }
            let localFraction = (fraction - previousFraction) / denominator
            let createdEntityID = try splitSketchCurve(
                target: remainingTarget,
                fraction: .scalar(localFraction),
                objectRegistry: objectRegistry
            )
            createdEntityIDs.append(createdEntityID)
            remainingTarget = SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(
                    SelectionComponentID.sketchEntity(
                        featureID: targetSelection.featureID,
                        entityID: createdEntityID
                    )
                )
            )
            previousFraction = fraction
        }
        return createdEntityIDs
    }

    private func editableSketchEntity(
        for target: SelectionTarget,
        operationName: String
    ) throws -> (
        featureID: FeatureID,
        entityID: SketchEntityID,
        feature: FeatureNode,
        sketch: Sketch,
        entity: SketchEntity
    ) {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch scene node."
            )
        }
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch entity selection target."
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable sketch feature."
            )
        }
        guard let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an existing sketch entity."
            )
        }
        return (
            featureID: featureID,
            entityID: reference.entityID,
            feature: feature,
            sketch: sketch,
            entity: entity
        )
    }

    private func editableSketchEntityBase(
        for target: SelectionTarget,
        operationName: String
    ) throws -> EditableSketchEntitySelection {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch scene node."
            )
        }
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch entity selection target."
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable sketch feature."
            )
        }
        guard let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an existing sketch entity."
            )
        }
        return (
            featureID: featureID,
            entityID: reference.entityID,
            feature: feature,
            sketch: sketch,
            entity: entity
        )
    }

    private func curveCurvatureDisplayComponentID(
        for target: SelectionTarget
    ) throws -> SelectionComponentID {
        let selection = try editableSketchEntity(
            for: target,
            operationName: "Curve curvature display"
        )
        switch selection.entity {
        case .line,
             .circle,
             .arc,
             .spline:
            return .sketchEntity(
                featureID: selection.featureID,
                entityID: selection.entityID
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Curve curvature display requires a source curve entity, not a point."
            )
        }
    }

    private func pointDisplayComponentID(
        for target: SelectionTarget
    ) throws -> SelectionComponentID {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Point display requires a sketch scene node."
            )
        }
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchEntityBaseReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Point display requires a sketch curve, point handle, or control point selection target."
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Point display selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[reference.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Point display requires an existing sketch entity."
            )
        }
        switch entity {
        case .line,
             .circle,
             .arc,
             .spline:
            return .sketchEntity(featureID: featureID, entityID: reference.entityID)
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Point display requires a source curve entity, not a standalone point."
            )
        }
    }

    private func slotLineChainPathPoints(
        for selection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        )
    ) throws -> [SlotProfileBuilder.PathPoint] {
        let vertices = try SlotLineChainResolver().resolve(
            sketch: selection.sketch,
            selectedLineID: selection.entityID
        )
        return try vertices.map { vertex in
            guard let resolved = try resolvedPoint(
                vertex.reference,
                in: selection.sketch,
                owner: "Slot source line chain"
            ) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source line chain requires line endpoint references."
                )
            }
            for connectedReference in vertex.connectedLineEndpointReferences {
                guard let connected = try resolvedPoint(
                    connectedReference,
                    in: selection.sketch,
                    owner: "Slot source line chain"
                ) else {
                    continue
                }
                let deltaX = connected.x - resolved.x
                let deltaY = connected.y - resolved.y
                guard deltaX * deltaX + deltaY * deltaY <= 1.0e-18 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source line chain requires coincident endpoints to resolve to the same point."
                    )
                }
            }
            return SlotProfileBuilder.PathPoint(
                point: try sketchPoint(vertex.reference, in: selection.sketch, owner: "Slot source line chain"),
                resolved: Point2D(x: resolved.x, y: resolved.y)
            )
        }
    }

    private func slotCurveChainPathSegments(
        for selection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        )
    ) throws -> [SlotProfileBuilder.CurvePathSegment] {
        let pathSegments = try SlotCurveChainResolver().resolve(
            sketch: selection.sketch,
            selectedEntityID: selection.entityID
        )
        return try pathSegments.map { segment in
            guard let entity = selection.sketch.entities[segment.entityID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Slot source curve chain requires existing sketch entities."
                )
            }
            switch entity {
            case .line:
                let start = try resolvedPathPoint(
                    segment.startReference,
                    in: selection.sketch,
                    owner: "Slot source curve chain"
                )
                let end = try resolvedPathPoint(
                    segment.endReference,
                    in: selection.sketch,
                    owner: "Slot source curve chain"
                )
                return .line(SlotProfileBuilder.LinePathSegment(start: start, end: end))
            case .arc(let arc):
                let center = try resolvedPathPoint(
                    .arcCenter(segment.entityID),
                    in: selection.sketch,
                    owner: "Slot source curve chain"
                )
                let radius = try resolvedPositiveLengthValue(
                    arc.radius,
                    owner: "Slot source curve chain arc radius"
                )
                let startAngle = try resolvedAngleValue(
                    arc.startAngle,
                    owner: "Slot source curve chain arc start angle"
                )
                let endAngle = try resolvedAngleValue(
                    arc.endAngle,
                    owner: "Slot source curve chain arc end angle"
                )
                let traversesForward: Bool
                switch (segment.startReference, segment.endReference) {
                case (.arcStart(let firstID), .arcEnd(let secondID)) where firstID == segment.entityID && secondID == segment.entityID:
                    traversesForward = true
                case (.arcEnd(let firstID), .arcStart(let secondID)) where firstID == segment.entityID && secondID == segment.entityID:
                    traversesForward = false
                default:
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source arc chain requires arc endpoint references."
                    )
                }
                return .arc(SlotProfileBuilder.ArcPathSegment(
                    center: center,
                    radius: radius,
                    startAngle: traversesForward ? startAngle : endAngle,
                    endAngle: traversesForward ? endAngle : startAngle,
                    sweepSign: traversesForward ? 1.0 : -1.0
                ))
            case .point, .circle, .spline:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source curve chain supports line and arc sketch entities."
                )
            }
        }
    }

    private func resolvedPathPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Point2D {
        guard let point = try resolvedPoint(reference, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-like sketch references."
            )
        }
        return Point2D(x: point.x, y: point.y)
    }

    private func sketchPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchPoint {
        switch reference {
        case .lineStart(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line(let line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return line.start
        case .lineEnd(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line(let line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return line.end
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires line endpoint references."
            )
        }
    }

    private func editableProfileRegion(
        for target: SelectionTarget,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> EditableProfileRegionSelection {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch scene node."
            )
        }
        guard case .region(let componentID) = target.component,
              let reference = componentID.profileRegionReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a source profile region selection target."
            )
        }
        guard reference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              feature.outputs.contains(where: { $0.role == .profile }),
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable sketch profile feature."
            )
        }
        guard sketch.entities.values.allSatisfy(Self.isLineSketchEntity) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports source regions made only from line sketch entities."
            )
        }

        let profiles: [Profile]
        do {
            let resolvedParameters = try ParameterResolver().resolve(cadDocument.parameters)
            profiles = try SketchProfileExtractor().extractProfiles(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: resolvedParameters
            )
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a supported closed source region: \(String(describing: error))"
            )
        }
        guard profiles.indices.contains(reference.profileIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) references a missing source profile region."
            )
        }

        return (
            featureID: featureID,
            profileIndex: reference.profileIndex,
            feature: feature,
            sketch: sketch,
            profile: profiles[reference.profileIndex]
        )
    }

    private static func isLineSketchEntity(_ entity: SketchEntity) -> Bool {
        if case .line = entity {
            return true
        }
        return false
    }

    private func offsetLine(
        _ line: SketchLine,
        distance: CADExpression,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) line start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) line start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) line end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) line end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        let normalX = -deltaY / length
        let normalY = deltaX / length
        return SketchLine(
            start: offsetPoint(
                line.start,
                distance: distance,
                normalX: normalX,
                normalY: normalY
            ),
            end: offsetPoint(
                line.end,
                distance: distance,
                normalX: normalX,
                normalY: normalY
            )
        )
    }

    private func offsetPoint(
        _ point: SketchPoint,
        distance: CADExpression,
        normalX: Double,
        normalY: Double
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(distance, .scalar(normalX))),
            y: .add(point.y, .multiply(distance, .scalar(normalY)))
        )
    }

    private func validateOffsetCurveVertexOptions(_ options: OffsetCurveOptions) throws {
        guard options.mode == .offset else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode requires a selected open curve target, not a vertex handle."
            )
        }
        guard options == OffsetCurveOptions() else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve vertex dispatch does not accept planar curve options such as symmetric output or gap fill."
            )
        }
    }

    private func offsetRadiusExpression(
        _ radius: CADExpression,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> CADExpression {
        let radiusMeters = try resolvedPositiveLengthValue(radius, owner: "\(owner) radius")
        guard radiusMeters + resolvedDistance > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) offset would collapse the radius."
            )
        }
        return .add(radius, distance)
    }

    private struct LineEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .lineStart(entityID) : .lineEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .lineEnd(entityID) : .lineStart(entityID)
        }
    }

    private struct ArcEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .arcStart(entityID) : .arcEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .arcEnd(entityID) : .arcStart(entityID)
        }
    }

    private enum SketchCurveEndpoint {
        case line(LineEndpoint)
        case arc(ArcEndpoint)

        var entityID: SketchEntityID {
            switch self {
            case .line(let endpoint):
                endpoint.entityID
            case .arc(let endpoint):
                endpoint.entityID
            }
        }

        var isStart: Bool {
            switch self {
            case .line(let endpoint):
                endpoint.isStart
            case .arc(let endpoint):
                endpoint.isStart
            }
        }

        var reference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.reference
            case .arc(let endpoint):
                endpoint.reference
            }
        }

        var oppositeReference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.oppositeReference
            case .arc(let endpoint):
                endpoint.oppositeReference
            }
        }
    }

    private enum ExtendCurveEndpoint {
        case line(LineEndpoint)
        case arc(ArcEndpoint)
        case spline(entityID: SketchEntityID, isStart: Bool, controlPointIndex: Int)

        var entityID: SketchEntityID {
            switch self {
            case .line(let endpoint):
                endpoint.entityID
            case .arc(let endpoint):
                endpoint.entityID
            case .spline(let entityID, _, _):
                entityID
            }
        }

        var isStart: Bool {
            switch self {
            case .line(let endpoint):
                endpoint.isStart
            case .arc(let endpoint):
                endpoint.isStart
            case .spline(_, let isStart, _):
                isStart
            }
        }

        var reference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.reference
            case .arc(let endpoint):
                endpoint.reference
            case .spline(let entityID, _, let controlPointIndex):
                .splineControlPoint(entity: entityID, index: controlPointIndex)
            }
        }
    }

    private struct LineSplitResult {
        var outer: SketchLine
        var corner: SketchLine
        var targetEndpointIsStart: Bool
    }

    private struct ArcSplitResult {
        var outer: SketchArc
        var corner: SketchArc
        var targetEndpointIsStart: Bool
    }

    private struct SketchCurveSplitResult {
        var outer: SketchEntity
        var corner: SketchEntity
        var targetEndpointIsStart: Bool
    }

    private func lineEndpoint(for reference: SketchReference) -> LineEndpoint? {
        switch reference {
        case .lineStart(let entityID):
            LineEndpoint(entityID: entityID, isStart: true)
        case .lineEnd(let entityID):
            LineEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    private func arcEndpoint(for reference: SketchReference) -> ArcEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            ArcEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            ArcEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    private func sketchCurveEndpoint(for reference: SketchReference) -> SketchCurveEndpoint? {
        if let lineEndpoint = lineEndpoint(for: reference) {
            return .line(lineEndpoint)
        }
        if let arcEndpoint = arcEndpoint(for: reference) {
            return .arc(arcEndpoint)
        }
        return nil
    }

    private func sketchCurveEndpoint(
        at point: (x: Double, y: Double),
        in sketch: Sketch,
        operationName: String
    ) throws -> (entityID: SketchEntityID, handle: SketchEntityPointHandle) {
        struct Candidate {
            var entityID: SketchEntityID
            var entity: SketchEntity
            var handle: SketchEntityPointHandle
            var distanceSquared: Double
        }

        let tolerance = 1.0e-8
        let toleranceSquared = tolerance * tolerance
        var candidates: [Candidate] = []

        func appendCandidate(
            entityID: SketchEntityID,
            entity: SketchEntity,
            handle: SketchEntityPointHandle,
            endpoint: (x: Double, y: Double)
        ) {
            let deltaX = point.x - endpoint.x
            let deltaY = point.y - endpoint.y
            let distanceSquared = deltaX * deltaX + deltaY * deltaY
            guard distanceSquared <= toleranceSquared else {
                return
            }
            candidates.append(
                Candidate(
                    entityID: entityID,
                    entity: entity,
                    handle: handle,
                    distanceSquared: distanceSquared
                )
            )
        }

        for (entityID, entity) in sketch.entities {
            switch entity {
            case .line(let line):
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .lineStart,
                    endpoint: try resolvedPoint(line.start, owner: "\(operationName) source line start")
                )
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .lineEnd,
                    endpoint: try resolvedPoint(line.end, owner: "\(operationName) source line end")
                )
            case .arc(let arc):
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .arcStart,
                    endpoint: try pointOnArc(
                        arc,
                        angle: arc.startAngle,
                        owner: "\(operationName) source arc start"
                    )
                )
                appendCandidate(
                    entityID: entityID,
                    entity: entity,
                    handle: .arcEnd,
                    endpoint: try pointOnArc(
                        arc,
                        angle: arc.endAngle,
                        owner: "\(operationName) source arc end"
                    )
                )
            case .point,
                 .circle,
                 .spline:
                continue
            }
        }

        let orderedCandidates = candidates.sorted { lhs, rhs in
            if abs(lhs.distanceSquared - rhs.distanceSquared) > 1.0e-24 {
                return lhs.distanceSquared < rhs.distanceSquared
            }
            if lhs.entityID.description != rhs.entityID.description {
                return lhs.entityID.description < rhs.entityID.description
            }
            return lhs.handle.rawValue < rhs.handle.rawValue
        }

        var adjacencyError: Error?
        for candidate in orderedCandidates {
            let reference = try sketchPointReference(
                entityID: candidate.entityID,
                entity: candidate.entity,
                handle: candidate.handle,
                operationName: operationName
            )
            guard let endpoint = sketchCurveEndpoint(for: reference),
                  isSupportedOffsetVertexCurveEntity(candidate.entity, endpoint: endpoint) else {
                continue
            }
            do {
                _ = try adjacentSketchCurveEndpoint(
                    to: reference,
                    in: sketch,
                    owner: operationName
                )
                return (entityID: candidate.entityID, handle: candidate.handle)
            } catch {
                adjacencyError = error
            }
        }

        if let adjacencyError {
            throw adjacencyError
        }
        throw EditorError(
            code: .referenceUnresolved,
            message: "\(operationName) could not resolve the generated vertex to a connected source line or arc endpoint."
        )
    }

    private func sketchSceneNodeID(
        for featureID: FeatureID,
        operationName: String
    ) throws -> SceneNodeID {
        guard let sceneNodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.reference == .sketch(featureID)
        })?.key else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) source sketch scene node was not found."
            )
        }
        return sceneNodeID
    }

    private func extendCurveEndpoint(
        for target: SelectionTarget,
        selection: EditableSketchEntitySelection,
        operationName: String
    ) throws -> ExtendCurveEndpoint {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch entity endpoint target."
            )
        }
        if let reference = componentID.sketchPointHandleReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) endpoint target does not match the selected source curve."
                )
            }
            switch reference.handle {
            case .lineStart:
                return .line(LineEndpoint(entityID: reference.entityID, isStart: true))
            case .lineEnd:
                return .line(LineEndpoint(entityID: reference.entityID, isStart: false))
            case .arcStart:
                return .arc(ArcEndpoint(entityID: reference.entityID, isStart: true))
            case .arcEnd:
                return .arc(ArcEndpoint(entityID: reference.entityID, isStart: false))
            case .point,
                 .circleCenter,
                 .arcCenter:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires a line endpoint, arc endpoint, or spline endpoint target."
                )
            }
        }
        if let reference = componentID.sketchControlPointReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) control point target does not match the selected source curve."
                )
            }
            guard case .spline(let spline) = selection.entity else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) control point targets are only valid for spline curves."
                )
            }
            if reference.index == 0 {
                return .spline(entityID: reference.entityID, isStart: true, controlPointIndex: 0)
            }
            if reference.index == spline.controlPoints.count - 1 {
                return .spline(
                    entityID: reference.entityID,
                    isStart: false,
                    controlPointIndex: reference.index
                )
            }
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a spline endpoint control point target."
            )
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) follows Plasticity Extend Curve endpoint selection; select a curve endpoint, not the whole curve."
        )
    }

    private func adjacentSketchCurveEndpoint(
        to reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (reference: SketchReference, endpoint: SketchCurveEndpoint, entity: SketchEntity) {
        let matches = sketch.constraints.compactMap { constraint -> SketchReference? in
            guard case .coincident(let first, let second) = constraint else {
                return nil
            }
            if first == reference {
                return second
            }
            if second == reference {
                return first
            }
            return nil
        }
        let curveEndpointMatches = matches.compactMap { candidate -> (SketchReference, SketchCurveEndpoint, SketchEntity)? in
            guard let endpoint = sketchCurveEndpoint(for: candidate),
                  let entity = sketch.entities[endpoint.entityID],
                  isSupportedOffsetVertexCurveEntity(entity, endpoint: endpoint) else {
                return nil
            }
            return (candidate, endpoint, entity)
        }
        guard curveEndpointMatches.count == 1,
              let match = curveEndpointMatches.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires exactly one adjacent line or arc endpoint at the selected vertex."
            )
        }
        return match
    }

    private struct SketchCornerTreatmentSelection {
        var selectedEndpoint: SketchCurveEndpoint
        var adjacentEndpoint: SketchCurveEndpoint
        var selectedEntity: SketchEntity
        var adjacentEntity: SketchEntity
    }

    private struct SketchCornerTreatmentResult {
        var selectedEntity: SketchEntity
        var adjacentEntity: SketchEntity
        var insertedEntity: SketchEntity
        var selectedInsertedReference: SketchReference
        var adjacentInsertedReference: SketchReference
    }

    private struct SketchCornerEndpointGeometry {
        var endpoint: SketchCurveEndpoint
        var entity: SketchEntity
        var vertex: SketchCornerPoint
        var length: Double
        var unit: SketchCornerPoint
        var arc: SketchCornerArcGeometry?
    }

    private struct SketchCornerArcGeometry {
        var center: SketchCornerPoint
        var radius: Double
        var startAngle: Double
        var endAngle: Double
        var span: Double

        func point(atDistanceFromEndpoint distance: Double, endpoint: ArcEndpoint) -> SketchCornerPoint {
            let angle = endpoint.isStart
                ? startAngle + distance / radius
                : endAngle - distance / radius
            return point(atStorageAngle: angle)
        }

        func point(atStorageAngle angle: Double) -> SketchCornerPoint {
            SketchCornerPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        func storageAngle(
            for point: SketchCornerPoint,
            owner: String,
            tolerance: Double
        ) throws -> Double {
            let radialDistance = center.distance(to: point)
            guard abs(radialDistance - radius) <= max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a point outside the source arc."
                )
            }
            let rawAngle = atan2(point.y - center.y, point.x - center.x)
            let offset = nonnegativeAngleSpan(
                from: startAngle,
                to: rawAngle
            )
            guard offset >= -tolerance,
                  offset <= span + max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a point outside the source arc span."
                )
            }
            return startAngle + min(max(offset, 0.0), span)
        }

        func pathDistanceFromEndpoint(
            to point: SketchCornerPoint,
            endpoint: ArcEndpoint,
            owner: String,
            tolerance: Double
        ) throws -> Double {
            let angle = try storageAngle(for: point, owner: owner, tolerance: tolerance)
            let spanFromEndpoint = endpoint.isStart
                ? angle - startAngle
                : endAngle - angle
            let distance = max(0.0, min(spanFromEndpoint, span)) * radius
            guard distance <= radius * span + max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a point outside the source arc span."
                )
            }
            return distance
        }

        private func nonnegativeAngleSpan(
            from startAngle: Double,
            to endAngle: Double
        ) -> Double {
            let fullCircle = Double.pi * 2.0
            var span = endAngle - startAngle
            while span < 0.0 {
                span += fullCircle
            }
            while span > fullCircle {
                span -= fullCircle
            }
            return span
        }
    }

    private struct SketchCornerFilletCandidate {
        var center: SketchCornerPoint
        var selectedPoint: SketchCornerPoint
        var adjacentPoint: SketchCornerPoint
        var score: Double
    }

    private enum SketchCornerOffsetPrimitive {
        case line(point: SketchCornerPoint, direction: SketchCornerPoint)
        case circle(center: SketchCornerPoint, radius: Double)
    }

    private struct SketchCornerPoint: Equatable, Sendable {
        var x: Double
        var y: Double

        var leftNormal: SketchCornerPoint {
            SketchCornerPoint(x: -y, y: x)
        }

        func adding(_ other: SketchCornerPoint) -> SketchCornerPoint {
            SketchCornerPoint(x: x + other.x, y: y + other.y)
        }

        func subtracting(_ other: SketchCornerPoint) -> SketchCornerPoint {
            SketchCornerPoint(x: x - other.x, y: y - other.y)
        }

        func scaled(by scale: Double) -> SketchCornerPoint {
            SketchCornerPoint(x: x * scale, y: y * scale)
        }

        func dot(_ other: SketchCornerPoint) -> Double {
            x * other.x + y * other.y
        }

        func cross(_ other: SketchCornerPoint) -> Double {
            x * other.y - y * other.x
        }

        func distance(to other: SketchCornerPoint) -> Double {
            hypot(x - other.x, y - other.y)
        }

        func normalized(owner: String, tolerance: Double) throws -> SketchCornerPoint {
            let length = hypot(x, y)
            guard length > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a stable direction."
                )
            }
            return scaled(by: 1.0 / length)
        }
    }

    private func sketchCornerTreatmentSelection(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget?,
        selection: EditableSketchEntitySelection
    ) throws -> SketchCornerTreatmentSelection {
        if let adjacentTarget {
            return try sketchCornerTreatmentSelectionFromCurvePair(
                target: target,
                adjacentTarget: adjacentTarget,
                selection: selection
            )
        }
        return try sketchCornerTreatmentSelectionFromEndpoint(
            target: target,
            selection: selection
        )
    }

    private func sketchCornerTreatmentSelectionFromEndpoint(
        target: SelectionTarget,
        selection: EditableSketchEntitySelection
    ) throws -> SketchCornerTreatmentSelection {
        guard case .sketchEntity(let componentID) = target.component,
              let reference = componentID.sketchPointHandleReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment requires a selected source curve endpoint."
            )
        }
        guard reference.featureID == selection.featureID,
              reference.entityID == selection.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment endpoint target does not match the selected source curve."
            )
        }
        let selectedEndpoint: SketchCurveEndpoint
        switch reference.handle {
        case .lineStart:
            selectedEndpoint = .line(LineEndpoint(entityID: reference.entityID, isStart: true))
        case .lineEnd:
            selectedEndpoint = .line(LineEndpoint(entityID: reference.entityID, isStart: false))
        case .arcStart:
            selectedEndpoint = .arc(ArcEndpoint(entityID: reference.entityID, isStart: true))
        case .arcEnd:
            selectedEndpoint = .arc(ArcEndpoint(entityID: reference.entityID, isStart: false))
        case .point,
             .circleCenter,
             .arcCenter:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires a line or arc endpoint."
            )
        }
        guard isSupportedOffsetVertexCurveEntity(selection.entity, endpoint: selectedEndpoint) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment currently supports connected line or arc endpoints."
            )
        }
        let adjacent = try adjacentSketchCurveEndpoint(
            to: selectedEndpoint.reference,
            in: selection.sketch,
            owner: "Sketch corner treatment"
        )
        guard adjacent.endpoint.entityID != selectedEndpoint.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires two distinct source curves."
            )
        }
        return SketchCornerTreatmentSelection(
            selectedEndpoint: selectedEndpoint,
            adjacentEndpoint: adjacent.endpoint,
            selectedEntity: selection.entity,
            adjacentEntity: adjacent.entity
        )
    }

    private func sketchCornerTreatmentSelectionFromCurvePair(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget,
        selection: EditableSketchEntitySelection
    ) throws -> SketchCornerTreatmentSelection {
        let adjacentSelection = try editableSketchEntityBase(
            for: adjacentTarget,
            operationName: "Sketch corner treatment"
        )
        guard adjacentSelection.featureID == selection.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment curve-pair targets must belong to the same sketch."
            )
        }
        guard adjacentSelection.entityID != selection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires two distinct source curves."
            )
        }
        let selectedEndpoints = try sketchCornerTreatmentCandidateEndpoints(
            target: target,
            selection: selection
        )
        let adjacentEndpoints = try sketchCornerTreatmentCandidateEndpoints(
            target: adjacentTarget,
            selection: adjacentSelection
        )
        var matches: [(selected: SketchCurveEndpoint, adjacent: SketchCurveEndpoint)] = []
        for selectedEndpoint in selectedEndpoints {
            for adjacentEndpoint in adjacentEndpoints where sketchCornerTreatmentReferencesAreCoincident(
                selectedEndpoint.reference,
                adjacentEndpoint.reference,
                in: selection.sketch
            ) {
                matches.append((selectedEndpoint, adjacentEndpoint))
            }
        }
        guard matches.count == 1,
              let match = matches.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment curve-pair targets must share exactly one connected line or arc endpoint."
            )
        }
        return SketchCornerTreatmentSelection(
            selectedEndpoint: match.selected,
            adjacentEndpoint: match.adjacent,
            selectedEntity: selection.entity,
            adjacentEntity: adjacentSelection.entity
        )
    }

    private func sketchCornerTreatmentCandidateEndpoints(
        target: SelectionTarget,
        selection: EditableSketchEntitySelection
    ) throws -> [SketchCurveEndpoint] {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment requires sketch entity targets."
            )
        }
        if let reference = componentID.sketchPointHandleReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Sketch corner treatment endpoint target does not match the selected source curve."
                )
            }
            switch reference.handle {
            case .lineStart:
                return [.line(LineEndpoint(entityID: reference.entityID, isStart: true))]
            case .lineEnd:
                return [.line(LineEndpoint(entityID: reference.entityID, isStart: false))]
            case .arcStart:
                return [.arc(ArcEndpoint(entityID: reference.entityID, isStart: true))]
            case .arcEnd:
                return [.arc(ArcEndpoint(entityID: reference.entityID, isStart: false))]
            case .point,
                 .circleCenter,
                 .arcCenter:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch corner treatment requires line or arc curve endpoints."
                )
            }
        }
        guard let reference = componentID.sketchEntityReference,
              reference.featureID == selection.featureID,
              reference.entityID == selection.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch corner treatment curve-pair selection requires source curve targets."
            )
        }
        let endpoints = sketchCornerTreatmentEndpoints(
            entityID: reference.entityID,
            entity: selection.entity
        )
        guard endpoints.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment currently supports source line or arc curve targets."
            )
        }
        return endpoints
    }

    private func sketchCornerTreatmentEndpoints(
        entityID: SketchEntityID,
        entity: SketchEntity
    ) -> [SketchCurveEndpoint] {
        switch entity {
        case .line:
            [
                .line(LineEndpoint(entityID: entityID, isStart: true)),
                .line(LineEndpoint(entityID: entityID, isStart: false)),
            ]
        case .arc:
            [
                .arc(ArcEndpoint(entityID: entityID, isStart: true)),
                .arc(ArcEndpoint(entityID: entityID, isStart: false)),
            ]
        case .point,
             .circle,
             .spline:
            []
        }
    }

    private func sketchCornerTreatmentReferencesAreCoincident(
        _ first: SketchReference,
        _ second: SketchReference,
        in sketch: Sketch
    ) -> Bool {
        sketch.constraints.contains { constraint in
            guard case .coincident(let lhs, let rhs) = constraint else {
                return false
            }
            return (lhs == first && rhs == second) || (lhs == second && rhs == first)
        }
    }

    private func validateSketchCornerTreatment(
        selection: EditableSketchEntitySelection,
        corner: SketchCornerTreatmentSelection
    ) throws {
        let affectedEntityIDs: Set<SketchEntityID> = [
            corner.selectedEndpoint.entityID,
            corner.adjacentEndpoint.entityID,
        ]
        for entityID in affectedEntityIDs {
            guard productMetadata.bridgeCurveSources.values.contains(where: { source in
                source.featureID == selection.featureID && source.entityID == entityID
            }) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch corner treatment cannot edit a generated Bridge Curve source."
                )
            }
        }
        for constraint in selection.sketch.constraints where sketchCornerTreatmentBlocksConstraint(
            constraint,
            affectedEntityIDs: affectedEntityIDs,
            selectedReference: corner.selectedEndpoint.reference,
            adjacentReference: corner.adjacentEndpoint.reference
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment cannot preserve unsupported constraints attached to the changing corner yet."
            )
        }
    }

    private func sketchCornerTreatmentResult(
        corner: SketchCornerTreatmentSelection,
        distance: Double,
        treatment: SketchCornerTreatment,
        insertedEntityID: SketchEntityID
    ) throws -> SketchCornerTreatmentResult {
        let selectedGeometry = try sketchCornerEndpointGeometry(
            corner.selectedEntity,
            endpoint: corner.selectedEndpoint,
            owner: "Sketch corner treatment selected curve"
        )
        let adjacentGeometry = try sketchCornerEndpointGeometry(
            corner.adjacentEntity,
            endpoint: corner.adjacentEndpoint,
            owner: "Sketch corner treatment adjacent curve"
        )
        let vertexDistance = selectedGeometry.vertex.distance(to: adjacentGeometry.vertex)
        guard vertexDistance <= ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires coincident curve endpoints."
            )
        }

        let selectedPoint: SketchCornerPoint
        let adjacentPoint: SketchCornerPoint
        let insertedEntity: SketchEntity
        let selectedInsertedReference: SketchReference
        let adjacentInsertedReference: SketchReference
        switch treatment {
        case .fillet:
            let candidate = try sketchCornerFilletCandidate(
                selectedGeometry: selectedGeometry,
                adjacentGeometry: adjacentGeometry,
                radius: distance
            )
            selectedPoint = candidate.selectedPoint
            adjacentPoint = candidate.adjacentPoint
            let fillet = try sketchCornerFilletEntity(
                center: candidate.center,
                selectedPoint: candidate.selectedPoint,
                adjacentPoint: candidate.adjacentPoint,
                radius: distance,
                insertedEntityID: insertedEntityID
            )
            insertedEntity = fillet.entity
            selectedInsertedReference = fillet.selectedReference
            adjacentInsertedReference = fillet.adjacentReference
        case .chamfer:
            selectedPoint = try sketchCornerTreatmentPoint(
                from: selectedGeometry,
                distance: distance
            )
            adjacentPoint = try sketchCornerTreatmentPoint(
                from: adjacentGeometry,
                distance: distance
            )
            insertedEntity = .line(SketchLine(
                start: literalSketchPoint(selectedPoint),
                end: literalSketchPoint(adjacentPoint)
            ))
            selectedInsertedReference = .lineStart(insertedEntityID)
            adjacentInsertedReference = .lineEnd(insertedEntityID)
        }

        let selectedEntity = try curveBySettingEndpoint(
            corner.selectedEntity,
            geometry: selectedGeometry,
            point: selectedPoint,
            owner: "Sketch corner treatment selected curve"
        )
        let adjacentEntity = try curveBySettingEndpoint(
            corner.adjacentEntity,
            geometry: adjacentGeometry,
            point: adjacentPoint,
            owner: "Sketch corner treatment adjacent curve"
        )
        return SketchCornerTreatmentResult(
            selectedEntity: selectedEntity,
            adjacentEntity: adjacentEntity,
            insertedEntity: insertedEntity,
            selectedInsertedReference: selectedInsertedReference,
            adjacentInsertedReference: adjacentInsertedReference
        )
    }

    private func sketchCornerFilletCandidate(
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> SketchCornerFilletCandidate {
        if case .line = selectedGeometry.entity,
           case .line = adjacentGeometry.entity {
            return try sketchLineLineCornerFilletCandidate(
                selectedGeometry: selectedGeometry,
                adjacentGeometry: adjacentGeometry,
                radius: radius
            )
        }
        return try sketchCurveCornerFilletCandidate(
            selectedGeometry: selectedGeometry,
            adjacentGeometry: adjacentGeometry,
            radius: radius
        )
    }

    private func sketchLineLineCornerFilletCandidate(
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> SketchCornerFilletCandidate {
        let dot = selectedGeometry.unit.dot(adjacentGeometry.unit)
        let angle = acos(min(max(dot, -1.0), 1.0))
        guard angle > ModelingTolerance.standard.angle,
              abs(Double.pi - angle) > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment requires a non-collinear line corner."
            )
        }
        let tangent = tan(angle / 2.0)
        guard tangent > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner fillet radius is invalid for the selected corner."
            )
        }
        let trimDistance = radius / tangent
        try validateSketchCornerTrimDistance(
            trimDistance,
            selectedGeometry: selectedGeometry,
            adjacentGeometry: adjacentGeometry
        )
        let bisector = try selectedGeometry.unit.adding(adjacentGeometry.unit).normalized(
            owner: "Sketch corner fillet bisector",
            tolerance: ModelingTolerance.standard.distance
        )
        let sine = sin(angle / 2.0)
        guard sine > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner fillet radius is invalid for the selected corner."
            )
        }
        let centerDistance = radius / sine
        let center = selectedGeometry.vertex.adding(bisector.scaled(by: centerDistance))
        return SketchCornerFilletCandidate(
            center: center,
            selectedPoint: try sketchCornerTreatmentPoint(from: selectedGeometry, distance: trimDistance),
            adjacentPoint: try sketchCornerTreatmentPoint(from: adjacentGeometry, distance: trimDistance),
            score: trimDistance + trimDistance
        )
    }

    private func sketchCurveCornerFilletCandidate(
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> SketchCornerFilletCandidate {
        let selectedPrimitives = try sketchCornerOffsetPrimitives(
            for: selectedGeometry,
            radius: radius
        )
        let adjacentPrimitives = try sketchCornerOffsetPrimitives(
            for: adjacentGeometry,
            radius: radius
        )
        let tolerance = max(ModelingTolerance.standard.distance, radius * 1.0e-8)
        var candidates: [SketchCornerFilletCandidate] = []
        for selectedPrimitive in selectedPrimitives {
            for adjacentPrimitive in adjacentPrimitives {
                let centers = try sketchCornerOffsetIntersections(
                    first: selectedPrimitive,
                    second: adjacentPrimitive,
                    tolerance: tolerance
                )
                for center in centers {
                    let selectedPoints = try sketchCornerFilletTangentPoints(
                        center: center,
                        geometry: selectedGeometry,
                        radius: radius,
                        tolerance: tolerance
                    )
                    let adjacentPoints = try sketchCornerFilletTangentPoints(
                        center: center,
                        geometry: adjacentGeometry,
                        radius: radius,
                        tolerance: tolerance
                    )
                    for selectedPoint in selectedPoints {
                        for adjacentPoint in adjacentPoints {
                            do {
                                if let candidate = try validSketchCornerFilletCandidate(
                                    center: center,
                                    selectedPoint: selectedPoint,
                                    adjacentPoint: adjacentPoint,
                                    selectedGeometry: selectedGeometry,
                                    adjacentGeometry: adjacentGeometry,
                                    tolerance: tolerance
                                ) {
                                    candidates.append(candidate)
                                }
                            } catch let error as EditorError where error.code == .commandInvalid {
                                continue
                            } catch {
                                throw error
                            }
                        }
                    }
                }
            }
        }
        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment cannot construct a tangent fillet for the selected source curves."
            )
        }
        return best
    }

    private func validSketchCornerFilletCandidate(
        center: SketchCornerPoint,
        selectedPoint: SketchCornerPoint,
        adjacentPoint: SketchCornerPoint,
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry,
        tolerance: Double
    ) throws -> SketchCornerFilletCandidate? {
        let selectedDistance = try sketchCornerPathDistance(
            fromEndpointOf: selectedGeometry,
            to: selectedPoint,
            owner: "Sketch corner fillet selected tangent point",
            tolerance: tolerance
        )
        let adjacentDistance = try sketchCornerPathDistance(
            fromEndpointOf: adjacentGeometry,
            to: adjacentPoint,
            owner: "Sketch corner fillet adjacent tangent point",
            tolerance: tolerance
        )
        guard selectedDistance > tolerance,
              adjacentDistance > tolerance,
              selectedGeometry.length - selectedDistance > tolerance,
              adjacentGeometry.length - adjacentDistance > tolerance else {
            return nil
        }
        return SketchCornerFilletCandidate(
            center: center,
            selectedPoint: selectedPoint,
            adjacentPoint: adjacentPoint,
            score: selectedDistance + adjacentDistance
        )
    }

    private func sketchCornerOffsetPrimitives(
        for geometry: SketchCornerEndpointGeometry,
        radius: Double
    ) throws -> [SketchCornerOffsetPrimitive] {
        if let arc = geometry.arc {
            var radii = [arc.radius + radius]
            let innerRadius = abs(arc.radius - radius)
            if innerRadius > ModelingTolerance.standard.distance,
               radii.contains(where: { abs($0 - innerRadius) <= ModelingTolerance.standard.distance }) == false {
                radii.append(innerRadius)
            }
            return radii.map {
                .circle(center: arc.center, radius: $0)
            }
        }
        let normal = geometry.unit.leftNormal
        return [
            .line(point: geometry.vertex.adding(normal.scaled(by: radius)), direction: geometry.unit),
            .line(point: geometry.vertex.adding(normal.scaled(by: -radius)), direction: geometry.unit),
        ]
    }

    private func sketchCornerOffsetIntersections(
        first: SketchCornerOffsetPrimitive,
        second: SketchCornerOffsetPrimitive,
        tolerance: Double
    ) throws -> [SketchCornerPoint] {
        switch (first, second) {
        case (.line(let firstPoint, let firstDirection), .circle(let center, let radius)):
            return sketchCornerLineCircleIntersections(
                linePoint: firstPoint,
                lineDirection: firstDirection,
                circleCenter: center,
                circleRadius: radius,
                tolerance: tolerance
            )
        case (.circle, .line):
            return try sketchCornerOffsetIntersections(
                first: second,
                second: first,
                tolerance: tolerance
            )
        case (.circle(let firstCenter, let firstRadius), .circle(let secondCenter, let secondRadius)):
            return try sketchCornerCircleCircleIntersections(
                firstCenter: firstCenter,
                firstRadius: firstRadius,
                secondCenter: secondCenter,
                secondRadius: secondRadius,
                tolerance: tolerance
            )
        case (.line, .line):
            return []
        }
    }

    private func sketchCornerLineCircleIntersections(
        linePoint: SketchCornerPoint,
        lineDirection: SketchCornerPoint,
        circleCenter: SketchCornerPoint,
        circleRadius: Double,
        tolerance: Double
    ) -> [SketchCornerPoint] {
        let delta = circleCenter.subtracting(linePoint)
        let projection = delta.dot(lineDirection)
        let distanceSquared = delta.dot(delta) - projection * projection
        let radiusSquared = circleRadius * circleRadius
        let discriminant = radiusSquared - distanceSquared
        guard discriminant >= -tolerance else {
            return []
        }
        if abs(discriminant) <= tolerance {
            return [linePoint.adding(lineDirection.scaled(by: projection))]
        }
        let root = discriminant.squareRoot()
        return [
            linePoint.adding(lineDirection.scaled(by: projection - root)),
            linePoint.adding(lineDirection.scaled(by: projection + root)),
        ]
    }

    private func sketchCornerCircleCircleIntersections(
        firstCenter: SketchCornerPoint,
        firstRadius: Double,
        secondCenter: SketchCornerPoint,
        secondRadius: Double,
        tolerance: Double
    ) throws -> [SketchCornerPoint] {
        let centerVector = secondCenter.subtracting(firstCenter)
        let centerDistance = firstCenter.distance(to: secondCenter)
        guard centerDistance > tolerance else {
            return []
        }
        guard centerDistance <= firstRadius + secondRadius + tolerance,
              centerDistance >= abs(firstRadius - secondRadius) - tolerance else {
            return []
        }
        let direction = try centerVector.normalized(
            owner: "Sketch corner circle intersection",
            tolerance: tolerance
        )
        let along = (
            firstRadius * firstRadius - secondRadius * secondRadius + centerDistance * centerDistance
        ) / (2.0 * centerDistance)
        let heightSquared = firstRadius * firstRadius - along * along
        guard heightSquared >= -tolerance else {
            return []
        }
        let base = firstCenter.adding(direction.scaled(by: along))
        if abs(heightSquared) <= tolerance {
            return [base]
        }
        let normal = direction.leftNormal
        let height = heightSquared.squareRoot()
        return [
            base.adding(normal.scaled(by: height)),
            base.adding(normal.scaled(by: -height)),
        ]
    }

    private func sketchCornerFilletTangentPoints(
        center: SketchCornerPoint,
        geometry: SketchCornerEndpointGeometry,
        radius: Double,
        tolerance: Double
    ) throws -> [SketchCornerPoint] {
        if let arc = geometry.arc {
            let radial = center.subtracting(arc.center)
            let unit: SketchCornerPoint
            do {
                unit = try radial.normalized(
                    owner: "Sketch corner arc tangent",
                    tolerance: tolerance
                )
            } catch let error as EditorError where error.code == .commandInvalid {
                return []
            } catch {
                throw error
            }
            var points: [SketchCornerPoint] = []
            for point in [
                arc.center.adding(unit.scaled(by: arc.radius)),
                arc.center.adding(unit.scaled(by: -arc.radius)),
            ] {
                guard abs(point.distance(to: center) - radius) <= max(tolerance, radius * 1.0e-8) else {
                    continue
                }
                do {
                    _ = try sketchCornerPathDistance(
                        fromEndpointOf: geometry,
                        to: point,
                        owner: "Sketch corner arc tangent",
                        tolerance: tolerance
                    )
                    points.append(point)
                } catch let error as EditorError where error.code == .commandInvalid {
                    continue
                } catch {
                    throw error
                }
            }
            return points
        }
        let distance = center.subtracting(geometry.vertex).dot(geometry.unit)
        let point = geometry.vertex.adding(geometry.unit.scaled(by: distance))
        guard abs(point.distance(to: center) - radius) <= max(tolerance, radius * 1.0e-8) else {
            return []
        }
        return [point]
    }

    private func sketchCornerFilletEntity(
        center: SketchCornerPoint,
        selectedPoint: SketchCornerPoint,
        adjacentPoint: SketchCornerPoint,
        radius: Double,
        insertedEntityID: SketchEntityID
    ) throws -> (
        entity: SketchEntity,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) {
        let selectedAngle = atan2(selectedPoint.y - center.y, selectedPoint.x - center.x)
        let adjacentAngle = atan2(adjacentPoint.y - center.y, adjacentPoint.x - center.x)
        let selectedToAdjacentSpan = normalizedPositiveAngleSpan(
            from: selectedAngle,
            to: adjacentAngle
        )

        let startAngle: Double
        let endAngle: Double
        let selectedReference: SketchReference
        let adjacentReference: SketchReference
        if selectedToAdjacentSpan <= Double.pi {
            startAngle = selectedAngle
            endAngle = adjacentAngle
            selectedReference = .arcStart(insertedEntityID)
            adjacentReference = .arcEnd(insertedEntityID)
        } else {
            startAngle = adjacentAngle
            endAngle = selectedAngle
            selectedReference = .arcEnd(insertedEntityID)
            adjacentReference = .arcStart(insertedEntityID)
        }
        _ = try normalizedPartialArcSpan(
            startAngle: startAngle,
            endAngle: endAngle
        )

        return (
            entity: .arc(SketchArc(
                center: literalSketchPoint(center),
                radius: .length(radius, .meter),
                startAngle: .angle(startAngle, .radian),
                endAngle: .angle(endAngle, .radian)
            )),
            selectedReference: selectedReference,
            adjacentReference: adjacentReference
        )
    }

    private func constraintsAfterSketchCornerTreatment(
        _ constraints: [SketchConstraint],
        corner: SketchCornerTreatmentSelection,
        result: SketchCornerTreatmentResult
    ) -> [SketchConstraint] {
        var updated = constraints.filter { constraint in
            isOriginalSketchCornerCoincidence(
                constraint,
                selectedReference: corner.selectedEndpoint.reference,
                adjacentReference: corner.adjacentEndpoint.reference
            ) == false
        }
        updated.append(.coincident(
            corner.selectedEndpoint.reference,
            result.selectedInsertedReference
        ))
        updated.append(.coincident(
            result.adjacentInsertedReference,
            corner.adjacentEndpoint.reference
        ))
        return updated
    }

    private func dimensionsAfterSketchCornerTreatment(
        _ dimensions: [SketchDimension],
        affectedEntityIDs: Set<SketchEntityID>,
        in sketch: Sketch
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            guard dimensionReferencesAny(dimension, entityIDs: affectedEntityIDs) else {
                return dimension
            }
            return try refreshedSketchDimension(
                dimension,
                in: sketch,
                owner: "Sketch corner treatment dimension migration"
            )
        }
    }

    private func refreshedSketchDimension(
        _ dimension: SketchDimension,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchDimension {
        switch dimension {
        case .distance(let from, let to, _):
            let distance = try measuredSketchDistanceDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .distance(from: from, to: to, value: .length(distance, .meter))
        case .angle(let from, let to, _):
            let angle = try measuredSketchAngleDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .angle(from: from, to: to, value: .angle(angle, .radian))
        case .radius(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .radius(entity: entityID, value: .length(radius, .meter))
        case .diameter(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .diameter(entity: entityID, value: .length(radius * 2.0, .meter))
        }
    }

    private func measuredSketchDistanceDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed distance references."
            )
        }
        return hypot(second.x - first.x, second.y - first.y)
    }

    private func measuredSketchAngleDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        if let arcSpan = try measuredSketchArcSpanAngle(
            from: from,
            to: to,
            in: sketch,
            owner: owner
        ) {
            return arcSpan
        }
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed angle references."
            )
        }
        return atan2(second.y - first.y, second.x - first.x)
    }

    private func measuredSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        let entityID: SketchEntityID
        switch (from, to) {
        case (.arcStart(let firstID), .arcEnd(let secondID)) where firstID == secondID:
            entityID = firstID
        case (.arcEnd(let firstID), .arcStart(let secondID)) where firstID == secondID:
            entityID = firstID
        default:
            return try measuredConnectedSketchArcSpanAngle(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
        }
        guard let entity = sketch.entities[entityID],
              case .arc(let arc) = entity else {
            return nil
        }
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
    }

    private struct SketchArcPathEndpoint: Hashable {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .arcStart(entityID) : .arcEnd(entityID)
        }
    }

    private struct SketchArcPathGeometry {
        var entityID: SketchEntityID
        var center: (x: Double, y: Double)
        var radius: Double
        var startAngle: Double
        var endAngle: Double
        var span: Double

        var startEndpoint: SketchArcPathEndpoint {
            SketchArcPathEndpoint(entityID: entityID, isStart: true)
        }

        var endEndpoint: SketchArcPathEndpoint {
            SketchArcPathEndpoint(entityID: entityID, isStart: false)
        }
    }

    private func measuredConnectedSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        guard let fromEndpoint = sketchArcPathEndpoint(for: from),
              let toEndpoint = sketchArcPathEndpoint(for: to),
              let seedEntity = sketch.entities[fromEndpoint.entityID],
              case .arc(let seedArc) = seedEntity else {
            return nil
        }
        let seedGeometry = try sketchArcPathGeometry(
            entityID: fromEndpoint.entityID,
            arc: seedArc,
            owner: owner
        )
        var geometries: [SketchEntityID: SketchArcPathGeometry] = [:]
        for (entityID, entity) in sketch.entities {
            guard case .arc(let arc) = entity else {
                continue
            }
            let geometry = try sketchArcPathGeometry(
                entityID: entityID,
                arc: arc,
                owner: owner
            )
            guard sketchArcPathGeometry(geometry, matchesCircleOf: seedGeometry) else {
                continue
            }
            geometries[entityID] = geometry
        }
        guard geometries[toEndpoint.entityID] != nil else {
            return nil
        }
        let spans = [
            connectedSketchArcSpanAngle(
                from: fromEndpoint,
                to: toEndpoint,
                geometries: geometries
            ),
            connectedSketchArcSpanAngle(
                from: toEndpoint,
                to: fromEndpoint,
                geometries: geometries
            ),
        ]
            .compactMap { $0 }
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func sketchArcPathEndpoint(for reference: SketchReference) -> SketchArcPathEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func sketchArcPathGeometry(
        entityID: SketchEntityID,
        arc: SketchArc,
        owner: String
    ) throws -> SketchArcPathGeometry {
        let center = try resolvedPoint(arc.center, owner: "\(owner) arc center")
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return SketchArcPathGeometry(
            entityID: entityID,
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            span: try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        )
    }

    private func sketchArcPathGeometry(
        _ geometry: SketchArcPathGeometry,
        matchesCircleOf seed: SketchArcPathGeometry
    ) -> Bool {
        nearlyEqual(geometry.center.x, seed.center.x, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.center.y, seed.center.y, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.radius, seed.radius, tolerance: 1.0e-9)
    }

    private func connectedSketchArcSpanAngle(
        from start: SketchArcPathEndpoint,
        to target: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> Double? {
        func search(
            from current: SketchArcPathEndpoint,
            accumulatedSpan: Double,
            visitedArcs: Set<SketchEntityID>,
            visitedEndpoints: Set<SketchArcPathEndpoint>
        ) -> [Double] {
            if current == target {
                return [accumulatedSpan]
            }
            guard visitedEndpoints.contains(current) == false else {
                return []
            }
            let nextVisitedEndpoints = visitedEndpoints.union([current])
            var spans: [Double] = []
            if current.isStart,
               visitedArcs.contains(current.entityID) == false,
               let geometry = geometries[current.entityID] {
                spans.append(
                    contentsOf: search(
                        from: geometry.endEndpoint,
                        accumulatedSpan: accumulatedSpan + geometry.span,
                        visitedArcs: visitedArcs.union([current.entityID]),
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            for endpoint in matchingSketchArcPathEndpoints(
                current,
                geometries: geometries
            ) where endpoint != current {
                spans.append(
                    contentsOf: search(
                        from: endpoint,
                        accumulatedSpan: accumulatedSpan,
                        visitedArcs: visitedArcs,
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            return spans
        }
        let spans = search(
            from: start,
            accumulatedSpan: 0.0,
            visitedArcs: [],
            visitedEndpoints: []
        )
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func matchingSketchArcPathEndpoints(
        _ endpoint: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> [SketchArcPathEndpoint] {
        guard let source = geometries[endpoint.entityID] else {
            return []
        }
        let sourcePoint = sketchArcPathPoint(endpoint, geometry: source)
        return geometries.values.flatMap { geometry in
            [geometry.startEndpoint, geometry.endEndpoint].filter { candidate in
                let point = sketchArcPathPoint(candidate, geometry: geometry)
                return nearlyEqual(point.x, sourcePoint.x, tolerance: 1.0e-9) &&
                    nearlyEqual(point.y, sourcePoint.y, tolerance: 1.0e-9)
            }
        }
    }

    private func sketchArcPathPoint(
        _ endpoint: SketchArcPathEndpoint,
        geometry: SketchArcPathGeometry
    ) -> (x: Double, y: Double) {
        let angle = endpoint.isStart ? geometry.startAngle : geometry.endAngle
        return (
            x: geometry.center.x + cos(angle) * geometry.radius,
            y: geometry.center.y + sin(angle) * geometry.radius
        )
    }

    private func uniqueSketchArcPathSpans(_ spans: [Double]) -> [Double] {
        spans.reduce(into: []) { uniqueSpans, span in
            guard uniqueSpans.contains(where: { nearlyEqual($0, span, tolerance: 1.0e-9) }) == false else {
                return
            }
            uniqueSpans.append(span)
        }
    }

    private func measuredSketchCircularRadius(
        _ entityID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing circular entity."
            )
        }
        switch entity {
        case .circle(let circle):
            return try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
        case .arc(let arc):
            return try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        case .point,
             .line,
             .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a circle or arc dimension target."
            )
        }
    }

    private func sketchCornerTreatmentBlocksConstraint(
        _ constraint: SketchConstraint,
        affectedEntityIDs: Set<SketchEntityID>,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) -> Bool {
        if isOriginalSketchCornerCoincidence(
            constraint,
            selectedReference: selectedReference,
            adjacentReference: adjacentReference
        ) {
            return false
        }
        switch constraint {
        case .horizontal,
             .vertical:
            return false
        case .coincident(let first, let second):
            return sketchCornerTreatmentReferenceIsMoved(
                first,
                affectedEntityIDs: affectedEntityIDs,
                selectedReference: selectedReference,
                adjacentReference: adjacentReference
            ) || sketchCornerTreatmentReferenceIsMoved(
                second,
                affectedEntityIDs: affectedEntityIDs,
                selectedReference: selectedReference,
                adjacentReference: adjacentReference
            )
        case .fixed(let reference):
            return sketchCornerTreatmentReferenceIsMoved(
                reference,
                affectedEntityIDs: affectedEntityIDs,
                selectedReference: selectedReference,
                adjacentReference: adjacentReference
            )
        case .parallel,
             .perpendicular:
            return false
        case .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return affectedEntityIDs.contains(first) || affectedEntityIDs.contains(second)
        case .smoothSplineControlPoint(let entityID, _):
            return affectedEntityIDs.contains(entityID)
        case .splineEndpointTangent(let splineID, _, let lineID):
            return affectedEntityIDs.contains(splineID) || affectedEntityIDs.contains(lineID)
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return affectedEntityIDs.contains(first.splineID) ||
                affectedEntityIDs.contains(second.splineID)
        }
    }

    private func sketchCornerTreatmentReferenceIsMoved(
        _ reference: SketchReference,
        affectedEntityIDs: Set<SketchEntityID>,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) -> Bool {
        if reference == selectedReference || reference == adjacentReference {
            return true
        }
        switch reference {
        case .entity(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcRadius(let id),
             .splineControlPoint(let id, _):
            return affectedEntityIDs.contains(id)
        case .lineStart,
             .lineEnd,
             .arcStart,
             .arcEnd:
            return false
        }
    }

    private func isOriginalSketchCornerCoincidence(
        _ constraint: SketchConstraint,
        selectedReference: SketchReference,
        adjacentReference: SketchReference
    ) -> Bool {
        guard case .coincident(let first, let second) = constraint else {
            return false
        }
        return (first == selectedReference && second == adjacentReference) ||
            (first == adjacentReference && second == selectedReference)
    }

    private func sketchCornerEndpointGeometry(
        _ entity: SketchEntity,
        endpoint: SketchCurveEndpoint,
        owner: String
    ) throws -> SketchCornerEndpointGeometry {
        switch (entity, endpoint) {
        case (.line(let line), .line(let lineEndpoint)):
            let vertex = try resolvedPoint(lineEndpoint.isStart ? line.start : line.end, owner: "\(owner) vertex")
            let far = try resolvedPoint(lineEndpoint.isStart ? line.end : line.start, owner: "\(owner) far point")
            let vertexPoint = SketchCornerPoint(x: vertex.x, y: vertex.y)
            let farPoint = SketchCornerPoint(x: far.x, y: far.y)
            let delta = farPoint.subtracting(vertexPoint)
            let length = vertexPoint.distance(to: farPoint)
            guard length > ModelingTolerance.standard.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a line with non-zero length."
                )
            }
            return SketchCornerEndpointGeometry(
                endpoint: endpoint,
                entity: entity,
                vertex: vertexPoint,
                length: length,
                unit: delta.scaled(by: 1.0 / length),
                arc: nil
            )
        case (.arc(let arc), .arc(let arcEndpoint)):
            let center = try resolvedPoint(arc.center, owner: "\(owner) center")
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
            let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            let endpointAngle = arcEndpoint.isStart ? startAngle : endAngle
            let vertex = SketchCornerPoint(
                x: center.x + cos(endpointAngle) * radius,
                y: center.y + sin(endpointAngle) * radius
            )
            let unit = arcEndpoint.isStart
                ? SketchCornerPoint(x: -sin(endpointAngle), y: cos(endpointAngle))
                : SketchCornerPoint(x: sin(endpointAngle), y: -cos(endpointAngle))
            return SketchCornerEndpointGeometry(
                endpoint: endpoint,
                entity: entity,
                vertex: vertex,
                length: radius * span,
                unit: unit,
                arc: SketchCornerArcGeometry(
                    center: SketchCornerPoint(x: center.x, y: center.y),
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: startAngle + span,
                    span: span
                )
            )
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint target does not match the selected curve type."
            )
        }
    }

    private func sketchCornerTreatmentPoint(
        from geometry: SketchCornerEndpointGeometry,
        distance: Double
    ) throws -> SketchCornerPoint {
        try validateSketchCornerTrimDistance(
            distance,
            selectedGeometry: geometry,
            adjacentGeometry: nil
        )
        if let arc = geometry.arc,
           case .arc(let endpoint) = geometry.endpoint {
            return arc.point(atDistanceFromEndpoint: distance, endpoint: endpoint)
        }
        return geometry.vertex.adding(geometry.unit.scaled(by: distance))
    }

    private func validateSketchCornerTrimDistance(
        _ distance: Double,
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry?
    ) throws {
        guard distance.isFinite,
              distance > ModelingTolerance.standard.distance,
              selectedGeometry.length - distance > ModelingTolerance.standard.distance,
              adjacentGeometry.map({ $0.length - distance > ModelingTolerance.standard.distance }) ?? true else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment distance would collapse one of the adjacent curve sides."
            )
        }
    }

    private func sketchCornerPathDistance(
        fromEndpointOf geometry: SketchCornerEndpointGeometry,
        to point: SketchCornerPoint,
        owner: String,
        tolerance: Double
    ) throws -> Double {
        if let arc = geometry.arc,
           case .arc(let endpoint) = geometry.endpoint {
            return try arc.pathDistanceFromEndpoint(
                to: point,
                endpoint: endpoint,
                owner: owner,
                tolerance: tolerance
            )
        }
        let pointVector = point.subtracting(geometry.vertex)
        let cross = abs(pointVector.cross(geometry.unit))
        guard cross <= max(tolerance, geometry.length * tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced a point outside the source line."
            )
        }
        let distance = pointVector.dot(geometry.unit)
        guard distance >= -tolerance,
              distance <= geometry.length + tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced a point outside the source line."
            )
        }
        return min(max(distance, 0.0), geometry.length)
    }

    private func curveBySettingEndpoint(
        _ entity: SketchEntity,
        geometry: SketchCornerEndpointGeometry,
        point: SketchCornerPoint,
        owner: String
    ) throws -> SketchEntity {
        switch (entity, geometry.endpoint) {
        case (.line(let line), .line(let endpoint)):
            return .line(lineBySettingEndpoint(
                line,
                endpoint: endpoint,
                point: literalSketchPoint(point)
            ))
        case (.arc(let arc), .arc(let endpoint)):
            guard let arcGeometry = geometry.arc else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) is missing arc geometry."
                )
            }
            let angle = try arcGeometry.storageAngle(
                for: point,
                owner: owner,
                tolerance: ModelingTolerance.standard.distance
            )
            let updated = endpoint.isStart
                ? SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: .angle(angle, .radian),
                    endAngle: arc.endAngle
                )
                : SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: arc.startAngle,
                    endAngle: .angle(angle, .radian)
                )
            try validateArc(updated, owner: owner)
            return .arc(updated)
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint target does not match the selected curve type."
            )
        }
    }

    private func lineBySettingEndpoint(
        _ line: SketchLine,
        endpoint: LineEndpoint,
        point: SketchPoint
    ) -> SketchLine {
        if endpoint.isStart {
            return SketchLine(start: point, end: line.end)
        }
        return SketchLine(start: line.start, end: point)
    }

    private func literalSketchPoint(_ point: SketchCornerPoint) -> SketchPoint {
        literalSketchPoint(x: point.x, y: point.y)
    }

    private func literalSketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x, .meter),
            y: .length(y, .meter)
        )
    }

    private func normalizedNonnegativeAngleSpan(
        from startAngle: Double,
        to endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span < 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    private func normalizedPositiveAngleSpan(
        from startAngle: Double,
        to endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    private func isSupportedOffsetVertexCurveEntity(
        _ entity: SketchEntity,
        endpoint: SketchCurveEndpoint
    ) -> Bool {
        switch (entity, endpoint) {
        case (.line, .line),
             (.arc, .arc):
            return true
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            return false
        }
    }

    private func validateSketchCurveCanExtend(
        selection: EditableSketchEntitySelection,
        endpoint: ExtendCurveEndpoint,
        shape: ExtendCurveShape
    ) throws {
        guard selection.entityID == endpoint.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch curve extend endpoint target does not match the selected curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot edit a generated Bridge Curve source."
            )
        }

        switch (selection.entity, endpoint) {
        case (.line, .line):
            guard shape != .arc else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend Arc shape for line curves requires arc construction parameters."
                )
            }
        case (.arc, .arc):
            guard shape != .linear else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend Linear shape for arcs would create a new tangent line segment and is not supported yet."
                )
            }
        case (.spline(let spline), .spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend requires an open spline curve."
                )
            }
            guard shape == .linear else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend supports spline extension with Linear shape only until higher-continuity spline extension is implemented."
                )
            }
        case (.point, _),
             (.circle, _),
             (.line, _),
             (.arc, _),
             (.spline, _):
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend requires an endpoint target that belongs to the selected source curve type."
            )
        }

        for constraint in selection.sketch.constraints where sketchCurveExtendBlocksConstraint(
            constraint,
            entityID: selection.entityID,
            endpoint: endpoint,
            entity: selection.entity
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot preserve an attached constraint on the moved endpoint or whole curve yet."
            )
        }
        for dimension in selection.sketch.dimensions where sketchCurveExtendBlocksDimension(
            dimension,
            entityID: selection.entityID,
            entity: selection.entity
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot preserve dimensions attached to the changing curve extent yet."
            )
        }
    }

    private func extendedSketchCurveEntity(
        _ entity: SketchEntity,
        endpoint: ExtendCurveEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchEntity {
        switch (entity, endpoint) {
        case (.line(let line), .line(let lineEndpoint)):
            let extended = try extendedLine(
                line,
                endpoint: lineEndpoint,
                distance: distance,
                shape: shape,
                owner: owner
            )
            return .line(extended)
        case (.arc(let arc), .arc(let arcEndpoint)):
            let extended = try extendedArc(
                arc,
                endpoint: arcEndpoint,
                distance: distance,
                resolvedDistance: resolvedDistance,
                shape: shape,
                owner: owner
            )
            return .arc(extended)
        case (.spline(let spline), .spline):
            let extended = try extendedSpline(
                spline,
                endpoint: endpoint,
                distance: distance,
                shape: shape,
                owner: owner
            )
            return .spline(extended)
        case (.point, _),
             (.circle, _),
             (.line, _),
             (.arc, _),
             (.spline, _):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint target does not match the selected curve type."
            )
        }
    }

    private func extendedLine(
        _ line: SketchLine,
        endpoint: LineEndpoint,
        distance: CADExpression,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchLine {
        guard shape != .arc else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Arc shape for line curves requires arc construction parameters."
            )
        }
        let metrics = try resolvedLineMetrics(line, owner: owner)
        let directionX = cos(metrics.angleRadians) * (endpoint.isStart ? -1.0 : 1.0)
        let directionY = sin(metrics.angleRadians) * (endpoint.isStart ? -1.0 : 1.0)
        let extendedPoint = translatedSketchPoint(
            endpoint.isStart ? line.start : line.end,
            directionX: directionX,
            directionY: directionY,
            distance: distance
        )
        let extended = endpoint.isStart
            ? SketchLine(start: extendedPoint, end: line.end)
            : SketchLine(start: line.start, end: extendedPoint)
        _ = try resolvedLineMetrics(extended, owner: owner)
        return extended
    }

    private func extendedArc(
        _ arc: SketchArc,
        endpoint: ArcEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchArc {
        guard shape != .linear else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Linear shape for arcs would create a new tangent line segment and is not supported yet."
            )
        }
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let deltaAngle = resolvedDistance / radius
        guard span + deltaAngle < (2.0 * Double.pi) - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot extend an arc to a full or over-full circle."
            )
        }
        let deltaAngleExpression = CADExpression.multiply(
            .angle(1.0, .radian),
            .divide(distance, arc.radius)
        )
        let extended = endpoint.isStart
            ? SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: .subtract(arc.startAngle, deltaAngleExpression),
                endAngle: arc.endAngle
            )
            : SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: .add(arc.endAngle, deltaAngleExpression)
            )
        try validateArc(extended, owner: owner)
        return extended
    }

    private func extendedSpline(
        _ spline: SketchSpline,
        endpoint: ExtendCurveEndpoint,
        distance: CADExpression,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchSpline {
        guard case .spline(_, let isStart, _) = endpoint else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a spline endpoint target."
            )
        }
        guard shape == .linear else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) supports spline extension with Linear shape only."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an open spline curve."
            )
        }
        try validateSpline(spline, owner: owner)

        var updated = spline
        if isStart {
            let first = spline.controlPoints[0]
            let next = spline.controlPoints[1]
            let direction = try normalizedDirection(
                from: next,
                to: first,
                owner: "\(owner) start tangent"
            )
            updated.controlPoints = [
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance),
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance, scale: 2.0 / 3.0),
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance, scale: 1.0 / 3.0),
            ] + spline.controlPoints
        } else {
            let count = spline.controlPoints.count
            let previous = spline.controlPoints[count - 2]
            let last = spline.controlPoints[count - 1]
            let direction = try normalizedDirection(
                from: previous,
                to: last,
                owner: "\(owner) end tangent"
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance, scale: 1.0 / 3.0)
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance, scale: 2.0 / 3.0)
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance)
            )
        }
        try validateSpline(updated, owner: owner)
        return updated
    }

    private func translatedSketchPoint(
        _ point: SketchPoint,
        directionX: Double,
        directionY: Double,
        distance: CADExpression,
        scale: Double = 1.0
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(distance, .scalar(directionX * scale))),
            y: .add(point.y, .multiply(distance, .scalar(directionY * scale)))
        )
    }

    private func splineControlPointSlideDirection(
        in spline: SketchSpline,
        controlPointIndex: Int,
        direction: SplineControlPointSlideDirection,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let positiveU = try splineControlPointPositiveUDirection(
            in: spline,
            controlPointIndex: controlPointIndex,
            owner: owner
        )
        switch direction {
        case .positiveU:
            return positiveU
        case .negativeU:
            return (x: -positiveU.x, y: -positiveU.y)
        case .normal:
            return (x: -positiveU.y, y: positiveU.x)
        }
    }

    private func splineControlPointPositiveUDirection(
        in spline: SketchSpline,
        controlPointIndex: Int,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let controlPoints = spline.controlPoints
        guard controlPoints.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires at least two control points."
            )
        }
        if controlPointIndex == controlPoints.startIndex {
            return try normalizedDirection(
                from: controlPoints[controlPointIndex],
                to: controlPoints[controlPointIndex + 1],
                owner: "\(owner) control-cage U"
            )
        }
        if controlPointIndex == controlPoints.index(before: controlPoints.endIndex) {
            return try normalizedDirection(
                from: controlPoints[controlPointIndex - 1],
                to: controlPoints[controlPointIndex],
                owner: "\(owner) control-cage U"
            )
        }
        return try normalizedDirection(
            from: controlPoints[controlPointIndex - 1],
            to: controlPoints[controlPointIndex + 1],
            owner: "\(owner) control-cage U"
        )
    }

    private func normalizedDirection(
        from start: SketchPoint,
        to end: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let startX = try resolvedLengthValue(start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) direction must not collapse to zero."
            )
        }
        return (x: deltaX / length, y: deltaY / length)
    }

    private func sketchCurveExtendBlocksConstraint(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        endpoint: ExtendCurveEndpoint,
        entity: SketchEntity
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return first == endpoint.reference || second == endpoint.reference
        case .fixed(let reference):
            return reference == endpoint.reference || reference == .entity(entityID)
        case .horizontal(let id),
             .vertical(let id):
            if case .line = entity {
                return false
            }
            return id == entityID
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if case .arc = entity {
                return false
            }
            return first == entityID || second == entityID
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second):
            return first == entityID || second == entityID
        case .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .splineEndpointTangent(let splineID, _, let lineID):
            return splineID == entityID || lineID == entityID
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return first.splineID == entityID || second.splineID == entityID
        }
    }

    private func sketchCurveExtendBlocksDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) -> Bool {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            return sketchReference(from, references: entityID) ||
                sketchReference(to, references: entityID)
        case .radius(let id, _),
             .diameter(let id, _):
            if case .arc = entity {
                return false
            }
            return id == entityID
        }
    }

    private func splitPoint(
        on line: SketchLine,
        movingFrom endpoint: LineEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> SketchPoint {
        let vertex = endpoint.isStart ? line.start : line.end
        let far = endpoint.isStart ? line.end : line.start
        let vertexX = try resolvedLengthValue(vertex.x, owner: "\(owner) vertex x")
        let vertexY = try resolvedLengthValue(vertex.y, owner: "\(owner) vertex y")
        let farX = try resolvedLengthValue(far.x, owner: "\(owner) far x")
        let farY = try resolvedLengthValue(far.y, owner: "\(owner) far y")
        let deltaX = farX - vertexX
        let deltaY = farY - vertexY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a non-zero adjacent line."
            )
        }
        guard resolvedDistance < length - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) distance must be smaller than the adjacent line length."
            )
        }
        return SketchPoint(
            x: .add(vertex.x, .multiply(distance, .scalar(deltaX / length))),
            y: .add(vertex.y, .multiply(distance, .scalar(deltaY / length)))
        )
    }

    private func splitLine(
        _ line: SketchLine,
        targetEndpoint: LineEndpoint,
        splitPoint: SketchPoint
    ) -> LineSplitResult {
        if targetEndpoint.isStart {
            return LineSplitResult(
                outer: SketchLine(start: splitPoint, end: line.end),
                corner: SketchLine(start: line.start, end: splitPoint),
                targetEndpointIsStart: true
            )
        }
        return LineSplitResult(
            outer: SketchLine(start: line.start, end: splitPoint),
            corner: SketchLine(start: splitPoint, end: line.end),
            targetEndpointIsStart: false
        )
    }

    private func splitArc(
        _ arc: SketchArc,
        targetEndpoint: ArcEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> ArcSplitResult {
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let arcLength = radius * span
        guard resolvedDistance < arcLength - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) distance must be smaller than the adjacent arc length."
            )
        }
        let deltaAngle = CADExpression.multiply(
            .angle(1.0, .radian),
            .divide(distance, arc.radius)
        )
        if targetEndpoint.isStart {
            let splitAngle = CADExpression.add(arc.startAngle, deltaAngle)
            return ArcSplitResult(
                outer: SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: splitAngle,
                    endAngle: arc.endAngle
                ),
                corner: SketchArc(
                    center: arc.center,
                    radius: arc.radius,
                    startAngle: arc.startAngle,
                    endAngle: splitAngle
                ),
                targetEndpointIsStart: true
            )
        }
        let splitAngle = CADExpression.subtract(arc.endAngle, deltaAngle)
        return ArcSplitResult(
            outer: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: splitAngle
            ),
            corner: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: splitAngle,
                endAngle: arc.endAngle
            ),
            targetEndpointIsStart: false
        )
    }

    private func splitSketchCurve(
        _ entity: SketchEntity,
        targetEndpoint: SketchCurveEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> SketchCurveSplitResult {
        switch (entity, targetEndpoint) {
        case (.line(let line), .line(let endpoint)):
            let splitPoint = try splitPoint(
                on: line,
                movingFrom: endpoint,
                distance: distance,
                resolvedDistance: resolvedDistance,
                owner: owner
            )
            let split = splitLine(
                line,
                targetEndpoint: endpoint,
                splitPoint: splitPoint
            )
            return SketchCurveSplitResult(
                outer: .line(split.outer),
                corner: .line(split.corner),
                targetEndpointIsStart: split.targetEndpointIsStart
            )
        case (.arc(let arc), .arc(let endpoint)):
            let split = try splitArc(
                arc,
                targetEndpoint: endpoint,
                distance: distance,
                resolvedDistance: resolvedDistance,
                owner: owner
            )
            return SketchCurveSplitResult(
                outer: .arc(split.outer),
                corner: .arc(split.corner),
                targetEndpointIsStart: split.targetEndpointIsStart
            )
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line or arc endpoint that matches the selected curve."
            )
        }
    }

    private func splitReferences(
        endpoint: SketchCurveEndpoint,
        cornerID: SketchEntityID,
        split: SketchCurveSplitResult
    ) -> (
        outerSplit: SketchReference,
        cornerSplit: SketchReference,
        cornerVertex: SketchReference
    ) {
        switch endpoint {
        case .line(let lineEndpoint):
            if split.targetEndpointIsStart {
                return (
                    outerSplit: .lineStart(lineEndpoint.entityID),
                    cornerSplit: .lineEnd(cornerID),
                    cornerVertex: .lineStart(cornerID)
                )
            }
            return (
                outerSplit: .lineEnd(lineEndpoint.entityID),
                cornerSplit: .lineStart(cornerID),
                cornerVertex: .lineEnd(cornerID)
            )
        case .arc(let arcEndpoint):
            if split.targetEndpointIsStart {
                return (
                    outerSplit: .arcStart(arcEndpoint.entityID),
                    cornerSplit: .arcEnd(cornerID),
                    cornerVertex: .arcStart(cornerID)
                )
            }
            return (
                outerSplit: .arcEnd(arcEndpoint.entityID),
                cornerSplit: .arcStart(cornerID),
                cornerVertex: .arcEnd(cornerID)
            )
        }
    }

    private func offsetVertexConstraints(
        from constraints: [SketchConstraint],
        selectedReference: SketchReference,
        adjacentReference: SketchReference,
        selectedEndpoint: SketchCurveEndpoint,
        adjacentEndpoint: SketchCurveEndpoint,
        selectedCornerID: SketchEntityID,
        adjacentCornerID: SketchEntityID,
        selectedSplit: SketchCurveSplitResult,
        adjacentSplit: SketchCurveSplitResult
    ) -> [SketchConstraint] {
        var updated: [SketchConstraint] = []
        for constraint in constraints {
            switch constraint {
            case .coincident(let first, let second):
                if first == selectedReference ||
                    first == adjacentReference ||
                    second == selectedReference ||
                    second == adjacentReference {
                    continue
                }
                updated.append(constraint)
            case .horizontal(let entityID):
                updated.append(constraint)
                if entityID == selectedEndpoint.entityID,
                   case .line = selectedEndpoint {
                    updated.append(.horizontal(selectedCornerID))
                } else if entityID == adjacentEndpoint.entityID,
                          case .line = adjacentEndpoint {
                    updated.append(.horizontal(adjacentCornerID))
                }
            case .vertical(let entityID):
                updated.append(constraint)
                if entityID == selectedEndpoint.entityID,
                   case .line = selectedEndpoint {
                    updated.append(.vertical(selectedCornerID))
                } else if entityID == adjacentEndpoint.entityID,
                          case .line = adjacentEndpoint {
                    updated.append(.vertical(adjacentCornerID))
                }
            case .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                updated.append(constraint)
            }
        }

        let selectedReferences = splitReferences(
            endpoint: selectedEndpoint,
            cornerID: selectedCornerID,
            split: selectedSplit
        )
        let adjacentReferences = splitReferences(
            endpoint: adjacentEndpoint,
            cornerID: adjacentCornerID,
            split: adjacentSplit
        )
        updated.append(.coincident(selectedReferences.outerSplit, selectedReferences.cornerSplit))
        updated.append(.coincident(selectedReferences.cornerVertex, adjacentReferences.cornerVertex))
        updated.append(.coincident(adjacentReferences.cornerSplit, adjacentReferences.outerSplit))
        return updated
    }

    private func dimensionsAfterSketchVertexOffset(
        _ dimensions: [SketchDimension],
        affectedEntityIDs: Set<SketchEntityID>,
        selectedEndpoint: SketchCurveEndpoint,
        adjacentEndpoint: SketchCurveEndpoint,
        selectedCornerID: SketchEntityID,
        adjacentCornerID: SketchEntityID,
        selectedSplit: SketchCurveSplitResult,
        adjacentSplit: SketchCurveSplitResult,
        in sketch: Sketch
    ) throws -> [SketchDimension] {
        let selectedReferences = splitReferences(
            endpoint: selectedEndpoint,
            cornerID: selectedCornerID,
            split: selectedSplit
        )
        let adjacentReferences = splitReferences(
            endpoint: adjacentEndpoint,
            cornerID: adjacentCornerID,
            split: adjacentSplit
        )
        return try dimensions.map { dimension in
            guard dimensionReferencesAny(dimension, entityIDs: affectedEntityIDs) else {
                return dimension
            }
            let rewritten = try sketchDimensionAfterVertexOffset(
                dimension,
                selectedReference: selectedEndpoint.reference,
                selectedCornerVertex: selectedReferences.cornerVertex,
                adjacentReference: adjacentEndpoint.reference,
                adjacentCornerVertex: adjacentReferences.cornerVertex
            )
            try validateSketchVertexOffsetDimensionMigration(
                original: dimension,
                rewritten: rewritten,
                in: sketch
            )
            return try refreshedSketchDimension(
                rewritten,
                in: sketch,
                owner: "Sketch vertex offset dimension migration"
            )
        }
    }

    private func sketchDimensionAfterVertexOffset(
        _ dimension: SketchDimension,
        selectedReference: SketchReference,
        selectedCornerVertex: SketchReference,
        adjacentReference: SketchReference,
        adjacentCornerVertex: SketchReference
    ) throws -> SketchDimension {
        switch dimension {
        case .distance(let from, let to, let value):
            return .distance(
                from: sketchReferenceAfterVertexOffset(
                    from,
                    selectedReference: selectedReference,
                    selectedCornerVertex: selectedCornerVertex,
                    adjacentReference: adjacentReference,
                    adjacentCornerVertex: adjacentCornerVertex
                ),
                to: sketchReferenceAfterVertexOffset(
                    to,
                    selectedReference: selectedReference,
                    selectedCornerVertex: selectedCornerVertex,
                    adjacentReference: adjacentReference,
                    adjacentCornerVertex: adjacentCornerVertex
                ),
                value: value
            )
        case .angle(let from, let to, let value):
            let rewrittenFrom = sketchReferenceAfterVertexOffset(
                from,
                selectedReference: selectedReference,
                selectedCornerVertex: selectedCornerVertex,
                adjacentReference: adjacentReference,
                adjacentCornerVertex: adjacentCornerVertex
            )
            let rewrittenTo = sketchReferenceAfterVertexOffset(
                to,
                selectedReference: selectedReference,
                selectedCornerVertex: selectedCornerVertex,
                adjacentReference: adjacentReference,
                adjacentCornerVertex: adjacentCornerVertex
            )
            return .angle(from: rewrittenFrom, to: rewrittenTo, value: value)
        case .radius,
             .diameter:
            return dimension
        }
    }

    private func sketchReferenceAfterVertexOffset(
        _ reference: SketchReference,
        selectedReference: SketchReference,
        selectedCornerVertex: SketchReference,
        adjacentReference: SketchReference,
        adjacentCornerVertex: SketchReference
    ) -> SketchReference {
        if reference == selectedReference {
            return selectedCornerVertex
        }
        if reference == adjacentReference {
            return adjacentCornerVertex
        }
        return reference
    }

    private func validateSketchVertexOffsetDimensionMigration(
        original: SketchDimension,
        rewritten: SketchDimension,
        in sketch: Sketch
    ) throws {
        guard case .angle(let originalFrom, let originalTo, _) = original,
              case .angle(let rewrittenFrom, let rewrittenTo, _) = rewritten,
              sketchReferencesSingleArcSpan(originalFrom, originalTo),
              sketchReferencesSingleArcSpan(rewrittenFrom, rewrittenTo) == false else {
            return
        }
        guard try measuredSketchArcSpanAngle(
            from: rewrittenFrom,
            to: rewrittenTo,
            in: sketch,
            owner: "Sketch vertex offset dimension migration"
        ) != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch vertex offset cannot preserve arc span angle dimensions across disconnected split arcs."
            )
        }
    }

    private func sketchReferencesSingleArcSpan(
        _ first: SketchReference,
        _ second: SketchReference
    ) -> Bool {
        switch (first, second) {
        case (.arcStart(let firstID), .arcEnd(let secondID)),
             (.arcEnd(let firstID), .arcStart(let secondID)):
            return firstID == secondID
        default:
            return false
        }
    }

    private func validateSketchVertexOffsetConstraints(
        _ sketch: Sketch,
        affectedEntityIDs: Set<SketchEntityID>
    ) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case .coincident,
                 .horizontal,
                 .vertical:
                continue
            case .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints,
                 .fixed:
                if constraintReferencesAny(constraint, entityIDs: affectedEntityIDs) {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch vertex offset currently preserves only coincident and horizontal/vertical line constraints on affected line/arc vertices."
                    )
                }
            }
        }
    }

    private func dimensionReferencesAny(
        _ dimension: SketchDimension,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch dimension {
        case .distance(let first, let second, _),
             .angle(let first, let second, _):
            entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .radius(let entityID, _),
             .diameter(let entityID, _):
            entityIDs.contains(entityID)
        }
    }

    private func constraintReferencesAny(
        _ constraint: SketchConstraint,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .horizontal(let entityID),
             .vertical(let entityID),
             .smoothSplineControlPoint(let entityID, _):
            return entityIDs.contains(entityID)
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return entityIDs.contains(first) || entityIDs.contains(second)
        case .splineEndpointTangent(let splineID, _, let lineID):
            return entityIDs.contains(splineID) || entityIDs.contains(lineID)
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return entityIDs.contains(first.splineID) || entityIDs.contains(second.splineID)
        case .fixed(let reference):
            return entityIDs.contains(entityID(for: reference))
        }
    }

    private func entityID(for reference: SketchReference) -> SketchEntityID {
        switch reference {
        case .entity(let entityID),
             .lineStart(let entityID),
             .lineEnd(let entityID),
             .circleCenter(let entityID),
             .circleRadius(let entityID),
             .arcCenter(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID),
             .arcRadius(let entityID),
             .splineControlPoint(let entityID, _):
            entityID
        }
    }

    private func translatedSketchPoint(
        _ point: SketchPoint,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaXMeters: Double,
        deltaYMeters: Double
    ) -> SketchPoint {
        SketchPoint(
            x: translatedExpression(point.x, delta: deltaX, resolvedDelta: deltaXMeters),
            y: translatedExpression(point.y, delta: deltaY, resolvedDelta: deltaYMeters)
        )
    }

    private func movedArcEndpointAngle(
        _ arc: SketchArc,
        endpointAngle: CADExpression,
        deltaXMeters: Double,
        deltaYMeters: Double,
        owner: String
    ) throws -> CADExpression {
        let center = try resolvedPoint(arc.center, owner: "\(owner) center")
        let endpoint = try pointOnArc(arc, angle: endpointAngle, owner: owner)
        let movedX = endpoint.x + deltaXMeters
        let movedY = endpoint.y + deltaYMeters
        let deltaFromCenterX = movedX - center.x
        let deltaFromCenterY = movedY - center.y
        guard sqrt(deltaFromCenterX * deltaFromCenterX + deltaFromCenterY * deltaFromCenterY) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot move an arc endpoint onto the arc center."
            )
        }
        return .angle(atan2(deltaFromCenterY, deltaFromCenterX), .radian)
    }

    private func translatedExpression(
        _ expression: CADExpression,
        delta: CADExpression,
        resolvedDelta: Double
    ) -> CADExpression {
        guard abs(resolvedDelta) > 1.0e-12 else {
            return expression
        }
        return .add(expression, delta)
    }

    private func incompatibleSketchPointHandle(
        _ handle: SketchEntityPointHandle,
        entityKind: String,
        operationName: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "\(operationName) handle \(handle.rawValue) is not compatible with a \(entityKind) entity."
        )
    }

    private func sketchPointReference(
        entityID: SketchEntityID,
        entity: SketchEntity,
        handle: SketchEntityPointHandle,
        operationName: String
    ) throws -> SketchReference {
        switch entity {
        case .point:
            guard handle == .point else {
                throw incompatibleSketchPointHandle(handle, entityKind: "point", operationName: operationName)
            }
            return .entity(entityID)
        case .line:
            switch handle {
            case .lineStart:
                return .lineStart(entityID)
            case .lineEnd:
                return .lineEnd(entityID)
            case .point, .circleCenter, .arcCenter, .arcStart, .arcEnd:
                throw incompatibleSketchPointHandle(handle, entityKind: "line", operationName: operationName)
            }
        case .circle:
            guard handle == .circleCenter else {
                throw incompatibleSketchPointHandle(handle, entityKind: "circle", operationName: operationName)
            }
            return .circleCenter(entityID)
        case .arc:
            switch handle {
            case .arcCenter:
                return .arcCenter(entityID)
            case .arcStart:
                return .arcStart(entityID)
            case .arcEnd:
                return .arcEnd(entityID)
            case .point, .lineStart, .lineEnd, .circleCenter:
                throw incompatibleSketchPointHandle(handle, entityKind: "arc", operationName: operationName)
            }
        case .spline:
            throw incompatibleSketchPointHandle(handle, entityKind: "spline", operationName: operationName)
        }
    }

    private func resolvedLineMetrics(
        _ line: SketchLine,
        owner: String
    ) throws -> (length: Double, angleRadians: Double, angleDegrees: Double) {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) length must be greater than zero."
            )
        }
        let angleRadians = atan2(deltaY, deltaX)
        return (
            length: length,
            angleRadians: angleRadians,
            angleDegrees: angleRadians * 180.0 / .pi
        )
    }

    private func resizedLine(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + deltaX / currentLength * length,
                y: startY + deltaY / currentLength * length
            )
        )
    }

    private func resizedLinePreservingEnd(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: sketchPoint(
                x: endX - deltaX / currentLength * length,
                y: endY - deltaY / currentLength * length
            ),
            end: line.end
        )
    }

    private func angledLinePreservingStart(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + cos(angleRadians) * length,
                y: startY + sin(angleRadians) * length
            )
        )
    }

    private func angledLinePreservingEnd(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: sketchPoint(
                x: endX - cos(angleRadians) * length,
                y: endY - sin(angleRadians) * length
            ),
            end: line.end
        )
    }

    private func angularDistance(_ first: Double, _ second: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = (first - second).truncatingRemainder(dividingBy: fullCircle)
        if delta > Double.pi {
            delta -= fullCircle
        }
        if delta < -Double.pi {
            delta += fullCircle
        }
        return abs(delta)
    }

    private func lineOrientationDistance(_ first: Double, _ second: Double) -> Double {
        let period = Double.pi
        var delta = (first - second).truncatingRemainder(dividingBy: period)
        if delta > period / 2.0 {
            delta -= period
        }
        if delta < -period / 2.0 {
            delta += period
        }
        return abs(delta)
    }

    private func validateLineAngleDimensionAgainstDirectOrientationConstraints(
        _ angleRadians: Double,
        lineID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case .horizontal(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, 0.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a horizontal sketch constraint."
                    )
                }
            case .vertical(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, Double.pi / 2.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a vertical sketch constraint."
                    )
                }
            default:
                continue
            }
        }
    }

    private func radiusExpression(
        for kind: SketchEntityDimensionKind,
        value: CADExpression
    ) throws -> CADExpression {
        switch kind {
        case .radius:
            return value
        case .diameter:
            return .divide(value, .scalar(2.0))
        case .length, .angle:
            throw incompatibleSketchDimension(kind, entityKind: "circular")
        }
    }

    private func resolvedSketchEntityDimensionValue(
        _ expression: CADExpression,
        kind: SketchEntityDimensionKind,
        owner: String
    ) throws -> Double {
        switch kind {
        case .length, .radius, .diameter:
            return try resolvedLengthValue(expression, owner: owner)
        case .angle:
            return try resolvedAngleValue(expression, owner: owner)
        }
    }

    private func validateResolvedSketchEntityDimensionValue(
        _ value: Double,
        kind: SketchEntityDimensionKind,
        entity: SketchEntity
    ) throws {
        switch kind {
        case .length, .radius, .diameter:
            guard value > 0.0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch entity dimension must be greater than zero."
                )
            }
        case .angle:
            guard value.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch entity angle dimension must be finite."
                )
            }
            if case .arc = entity {
                guard value > 0.0 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch arc span angle dimension must be greater than zero."
                    )
                }
                guard value < Double.pi * 2.0 - ModelingTolerance.standard.angle else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch arc span angle dimension must be less than a full circle."
                    )
                }
            }
        }
    }

    private func incompatibleSketchDimension(
        _ kind: SketchEntityDimensionKind,
        entityKind: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch \(entityKind) does not support \(kind.rawValue) dimensions."
        )
    }

    private func convertedArc(
        from line: SketchLine,
        sagitta: Double,
        owner: String
    ) throws -> SketchArc {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let chordLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard chordLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }

        let midpointX = (startX + endX) / 2.0
        let midpointY = (startY + endY) / 2.0
        let normalX = -deltaY / chordLength
        let normalY = deltaX / chordLength
        let centerOffset = (chordLength * chordLength) / (8.0 * sagitta) - sagitta / 2.0
        let centerX = midpointX + normalX * centerOffset
        let centerY = midpointY + normalY * centerOffset
        let radius = sqrt(pow(chordLength / 2.0, 2.0) + centerOffset * centerOffset)
        guard radius.isFinite,
              radius > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced an invalid arc radius."
            )
        }

        let rawStartAngle = atan2(startY - centerY, startX - centerX)
        let rawEndAngle = atan2(endY - centerY, endX - centerX)
        let span = positiveArcSpan(startAngle: rawStartAngle, endAngle: rawEndAngle)
        _ = try normalizedPartialArcSpan(
            startAngle: rawStartAngle,
            endAngle: rawStartAngle + span
        )

        return SketchArc(
            center: sketchPoint(x: centerX, y: centerY),
            radius: .length(radius, .meter),
            startAngle: .angle(rawStartAngle, .radian),
            endAngle: .angle(rawStartAngle + span, .radian)
        )
    }

    private func convertedSpline(
        from line: SketchLine,
        owner: String
    ) throws -> SketchSpline {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchSpline(controlPoints: [
            sketchPoint(x: startX, y: startY),
            sketchPoint(x: startX + deltaX / 3.0, y: startY + deltaY / 3.0),
            sketchPoint(x: startX + deltaX * 2.0 / 3.0, y: startY + deltaY * 2.0 / 3.0),
            sketchPoint(x: endX, y: endY),
        ])
    }

    private func bridgeControlPoints(
        first: SketchCurveEndpointSample,
        firstTension: ResolvedBridgeCurveTension,
        second: SketchCurveEndpointSample,
        secondTension: ResolvedBridgeCurveTension
    ) -> [SketchPoint] {
        let p0 = first.sample.point
        let p6 = second.sample.point
        let chord = CADCore.Point2D(
            x: p6.x - p0.x,
            y: p6.y - p0.y
        )
        let chordLength = max(sqrt(chord.x * chord.x + chord.y * chord.y), 1.0e-9)
        let chordTangent = CADCore.Point2D(
            x: chord.x / chordLength,
            y: chord.y / chordLength
        )
        let jointFraction = firstTension.third / (firstTension.third + secondTension.third)
        let p3 = CADCore.Point2D(
            x: p0.x + chord.x * jointFraction,
            y: p0.y + chord.y * jointFraction
        )
        let p1 = CADCore.Point2D(
            x: p0.x + first.outgoingTangent.x * chordLength * firstTension.first / 6.0,
            y: p0.y + first.outgoingTangent.y * chordLength * firstTension.first / 6.0
        )
        let p2 = CADCore.Point2D(
            x: p3.x - chordTangent.x * chordLength * firstTension.second / 6.0,
            y: p3.y - chordTangent.y * chordLength * firstTension.second / 6.0
        )
        let p4 = CADCore.Point2D(
            x: p3.x + chordTangent.x * chordLength * secondTension.second / 6.0,
            y: p3.y + chordTangent.y * chordLength * secondTension.second / 6.0
        )
        let p5 = CADCore.Point2D(
            x: p6.x + second.outgoingTangent.x * chordLength * secondTension.first / 6.0,
            y: p6.y + second.outgoingTangent.y * chordLength * secondTension.first / 6.0
        )
        return [
            sketchPoint(x: p0.x, y: p0.y),
            sketchPoint(x: p1.x, y: p1.y),
            sketchPoint(x: p2.x, y: p2.y),
            sketchPoint(x: p3.x, y: p3.y),
            sketchPoint(x: p4.x, y: p4.y),
            sketchPoint(x: p5.x, y: p5.y),
            sketchPoint(x: p6.x, y: p6.y),
        ]
    }

    private struct ResolvedBridgeCurveTension {
        var first: Double
        var second: Double
        var third: Double
    }

    private func resolvedBridgeTension(
        _ tension: BridgeCurveTension,
        owner: String
    ) throws -> ResolvedBridgeCurveTension {
        let first = try resolvedPositiveScalarValue(tension.first, owner: "\(owner) 1")
        let second = try resolvedPositiveScalarValue(tension.second, owner: "\(owner) 2")
        let third = try resolvedPositiveScalarValue(tension.third, owner: "\(owner) 3")
        return ResolvedBridgeCurveTension(
            first: first,
            second: second,
            third: third
        )
    }

    private func bridgeContinuityConstraints(
        bridgeID: SketchEntityID,
        first: SketchCurveEndpointSample,
        second: SketchCurveEndpointSample,
        continuity: BridgeCurveContinuity
    ) -> [SketchConstraint] {
        return bridgeEndpointContinuityConstraints(
            bridgeID: bridgeID,
            bridgeEndpoint: .start,
            source: first,
            continuity: continuity.first
        ) + bridgeEndpointContinuityConstraints(
            bridgeID: bridgeID,
            bridgeEndpoint: .end,
            source: second,
            continuity: continuity.second
        )
    }

    private func bridgeEndpointContinuityConstraints(
        bridgeID: SketchEntityID,
        bridgeEndpoint: SketchSplineEndpoint,
        source: SketchCurveEndpointSample,
        continuity: BridgeCurveEndpointContinuity
    ) -> [SketchConstraint] {
        guard continuity != .g0 else {
            return []
        }
        let bridgeReference = SketchSplineEndpointReference(
            splineID: bridgeID,
            endpoint: bridgeEndpoint
        )
        switch source.kind {
        case .line(let lineID):
            switch continuity {
            case .g0:
                return []
            case .g1:
                return [
                    .splineEndpointTangent(
                        spline: bridgeID,
                        endpoint: bridgeEndpoint,
                        line: lineID
                    ),
                ]
            case .g2, .g3:
                return []
            }
        case .spline(let sourceReference):
            guard let sourceReference else {
                return []
            }
            switch continuity {
            case .g0:
                return []
            case .g1:
                return [
                    .tangentSplineEndpoints(
                        first: bridgeReference,
                        second: sourceReference
                    ),
                ]
            case .g2:
                return [
                    .smoothSplineEndpoints(
                        first: bridgeReference,
                        second: sourceReference
                    ),
                ]
            case .g3:
                return []
            }
        case .arc:
            return []
        }
    }

    private func bridgeOwnedConstraints(
        bridgeID: SketchEntityID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        firstSample: SketchCurveEndpointSample,
        secondSample: SketchCurveEndpointSample,
        continuity: BridgeCurveContinuity
    ) -> [SketchConstraint] {
        var constraints: [SketchConstraint] = []
        if let firstReference = firstSample.pointReference {
            constraints.append(.coincident(
                .splineControlPoint(entity: bridgeID, index: 0),
                firstReference
            ))
        }
        if let secondReference = secondSample.pointReference {
            constraints.append(.coincident(
                .splineControlPoint(entity: bridgeID, index: 6),
                secondReference
            ))
        }
        constraints += bridgeContinuityConstraints(
            bridgeID: bridgeID,
            first: firstSample,
            second: secondSample,
            continuity: continuity
        )
        return constraints
    }

    private func validateBridgeContinuitySupport(
        first: SketchCurveEndpointSample,
        second: SketchCurveEndpointSample,
        continuity: BridgeCurveContinuity
    ) throws {
        try validateBridgeEndpointContinuitySupport(
            first,
            continuity: continuity.first,
            owner: "Bridge curve first continuity"
        )
        try validateBridgeEndpointContinuitySupport(
            second,
            continuity: continuity.second,
            owner: "Bridge curve second continuity"
        )
    }

    private func validateBridgeEndpointContinuitySupport(
        _ sample: SketchCurveEndpointSample,
        continuity: BridgeCurveEndpointContinuity,
        owner: String
    ) throws {
        switch continuity {
        case .g0:
            return
        case .g1:
            guard supportsPersistentBridgeTangency(sample) else {
                throw unsupportedBridgeContinuity(
                    "\(owner) G1 currently requires a line or spline endpoint."
                )
            }
        case .g2:
            guard supportsPersistentBridgeSmoothness(sample) else {
                throw unsupportedBridgeContinuity(
                    "\(owner) G2 currently requires a spline endpoint."
                )
            }
        case .g3:
            throw unsupportedBridgeContinuity(
                "\(owner) G3 requires a higher-order bridge constraint that is not implemented yet."
            )
        }
    }

    private func supportsPersistentBridgeTangency(
        _ sample: SketchCurveEndpointSample
    ) -> Bool {
        switch sample.kind {
        case .line:
            sample.pointReference != nil
        case .spline(let sourceReference):
            sourceReference != nil && sample.pointReference != nil
        case .arc:
            false
        }
    }

    private func supportsPersistentBridgeSmoothness(
        _ sample: SketchCurveEndpointSample
    ) -> Bool {
        switch sample.kind {
        case .spline(let sourceReference):
            sourceReference != nil && sample.pointReference != nil
        case .line, .arc:
            false
        }
    }

    private func validateDistinctBridgeEndpointSamples(
        first: SketchCurveEndpointSample,
        second: SketchCurveEndpointSample
    ) throws {
        let dx = first.sample.point.x - second.sample.point.x
        let dy = first.sample.point.y - second.sample.point.y
        guard hypot(dx, dy) > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoints must resolve to two distinct points."
            )
        }
    }

    private struct TrimmedBridgeCurveEndpointSource {
        var entity: SketchEntity
        var endpointReference: SketchReference
    }

    private func validateBridgeCurveTrimDistinctSourceEntities(
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint
    ) throws {
        guard bridgeCurveEndpointRequiresTrim(firstEndpoint) || bridgeCurveEndpointRequiresTrim(secondEndpoint),
              let firstEntityID = bridgeCurveEndpointEntityID(firstEndpoint),
              let secondEntityID = bridgeCurveEndpointEntityID(secondEndpoint),
              firstEntityID == secondEntityID else {
            return
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Bridge curve trim cannot rewrite a source curve referenced by both bridge endpoints in one command."
        )
    }

    private func bridgeCurveEndpointRequiresTrim(_ endpoint: BridgeCurveEndpoint) -> Bool {
        guard let parameter = endpoint.parameter else {
            return false
        }
        guard case .constant(let quantity) = parameter,
              quantity.kind == .scalar else {
            return true
        }
        return quantity.value > ModelingTolerance.standard.distance
            && quantity.value < 1.0 - ModelingTolerance.standard.distance
    }

    private func trimBridgeCurveSourceEndpoint(
        _ endpoint: BridgeCurveEndpoint,
        in sketch: inout Sketch,
        owner: String
    ) throws -> BridgeCurveEndpoint {
        guard let parameterExpression = endpoint.parameter else {
            return endpoint
        }
        let parameter = try resolvedScalarValue(
            parameterExpression,
            owner: "\(owner) value"
        )
        guard parameter > ModelingTolerance.standard.distance,
              parameter < 1.0 - ModelingTolerance.standard.distance else {
            return endpoint
        }
        guard let entityID = bridgeCurveEndpointEntityID(endpoint),
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a line, arc, or spline curve position."
            )
        }
        try validateBridgeCurveTrimCanRewriteEntity(
            entityID: entityID,
            sketch: sketch,
            owner: owner
        )
        let trimmed = try trimmedBridgeCurveEndpointSource(
            entity,
            entityID: entityID,
            parameter: parameter,
            keepsBeforeEndpoint: endpoint.reversesSense == false,
            owner: owner
        )
        sketch.entities[entityID] = trimmed.entity
        return BridgeCurveEndpoint(
            reference: trimmed.endpointReference,
            tension: endpoint.tension
        )
    }

    private func validateBridgeCurveTrimCanRewriteEntity(
        entityID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        let hasRelatedConstraint = sketch.constraints.contains { constraint in
            sketchConstraint(constraint, references: entityID)
        }
        guard hasRelatedConstraint == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot rewrite a source curve that already has constraints."
            )
        }
        let hasRelatedDimension = sketch.dimensions.contains { dimension in
            sketchDimension(dimension, references: entityID)
        }
        guard hasRelatedDimension == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot rewrite a source curve that already has dimensions."
            )
        }
    }

    private func trimmedBridgeCurveEndpointSource(
        _ entity: SketchEntity,
        entityID: SketchEntityID,
        parameter: Double,
        keepsBeforeEndpoint: Bool,
        owner: String
    ) throws -> TrimmedBridgeCurveEndpointSource {
        switch entity {
        case .line(let line):
            let splitPoint = try splitPoint(
                on: line,
                fraction: parameter,
                owner: owner
            )
            if keepsBeforeEndpoint {
                let trimmed = SketchLine(start: line.start, end: splitPoint)
                _ = try resolvedLineMetrics(trimmed, owner: owner)
                return TrimmedBridgeCurveEndpointSource(
                    entity: .line(trimmed),
                    endpointReference: .lineEnd(entityID)
                )
            }
            let trimmed = SketchLine(start: splitPoint, end: line.end)
            _ = try resolvedLineMetrics(trimmed, owner: owner)
            return TrimmedBridgeCurveEndpointSource(
                entity: .line(trimmed),
                endpointReference: .lineStart(entityID)
            )
        case .arc(let arc):
            let split = try splitArc(arc, fraction: parameter, owner: owner)
            if keepsBeforeEndpoint {
                try validateArc(split.retained, owner: owner)
                return TrimmedBridgeCurveEndpointSource(
                    entity: .arc(split.retained),
                    endpointReference: .arcEnd(entityID)
                )
            }
            try validateArc(split.new, owner: owner)
            return TrimmedBridgeCurveEndpointSource(
                entity: .arc(split.new),
                endpointReference: .arcStart(entityID)
            )
        case .spline(let spline):
            let split = try splitSpline(spline, fraction: parameter, owner: owner)
            if keepsBeforeEndpoint {
                try validateSpline(split.retained, owner: owner)
                return TrimmedBridgeCurveEndpointSource(
                    entity: .spline(split.retained),
                    endpointReference: .splineControlPoint(
                        entity: entityID,
                        index: split.retained.controlPoints.count - 1
                    )
                )
            }
            try validateSpline(split.new, owner: owner)
            return TrimmedBridgeCurveEndpointSource(
                entity: .spline(split.new),
                endpointReference: .splineControlPoint(entity: entityID, index: 0)
            )
        case .point,
             .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line, arc, or spline curve position."
            )
        }
    }

    private func bridgeCurveEndpointEntityID(_ endpoint: BridgeCurveEndpoint) -> SketchEntityID? {
        switch endpoint.reference {
        case let .entity(entityID),
             let .lineStart(entityID),
             let .lineEnd(entityID),
             let .arcStart(entityID),
             let .arcEnd(entityID),
             let .splineControlPoint(entityID, _):
            return entityID
        case .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    private func unsupportedBridgeContinuity(_ message: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: message
        )
    }

    private func bridgeEndpointReferencesEntity(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case let .entity(referenceEntityID),
             let .lineStart(referenceEntityID),
             let .lineEnd(referenceEntityID),
             let .circleCenter(referenceEntityID),
             let .circleRadius(referenceEntityID),
             let .arcCenter(referenceEntityID),
             let .arcStart(referenceEntityID),
             let .arcEnd(referenceEntityID),
             let .arcRadius(referenceEntityID),
             let .splineControlPoint(referenceEntityID, _):
            referenceEntityID == entityID
        }
    }

    private func bridgeEndpointReferencesEntity(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> Bool {
        bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID)
    }

    private func appendBridgeConstraint(
        _ constraint: SketchConstraint,
        to sketch: inout Sketch
    ) {
        guard sketch.constraints.contains(constraint) == false else {
            return
        }
        sketch.constraints.append(constraint)
    }

    private func positiveArcSpan(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    private func constraintsAfterLineToArcConversion(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID
    ) -> [SketchConstraint] {
        constraints.compactMap { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    rewriteLineEndpointReference(first, entityID: entityID),
                    rewriteLineEndpointReference(second, entityID: entityID)
                )
            case .horizontal(let id), .vertical(let id):
                return id == entityID ? nil : constraint
            case .parallel(let first, let second),
                 .perpendicular(let first, let second),
                 .equalLength(let first, let second),
                 .tangent(let first, let second):
                return first == entityID || second == entityID ? nil : constraint
            case .concentric, .equalRadius:
                return constraint
            case .smoothSplineControlPoint:
                return constraint
            case .splineEndpointTangent(_, _, let lineID):
                return lineID == entityID ? nil : constraint
            case .tangentSplineEndpoints,
                 .smoothSplineEndpoints:
                return constraint
            case .fixed(let reference):
                return .fixed(
                    rewriteLineEndpointReference(reference, entityID: entityID)
                )
            }
        }
    }

    private func dimensionsAfterLineToArcConversion(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteLineEndpointReference(from, entityID: entityID),
                    to: rewriteLineEndpointReference(to, entityID: entityID),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteLineEndpointReference(from, entityID: entityID),
                    to: rewriteLineEndpointReference(to, entityID: entityID),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private func validateLineCanConvertToSpline(
        entityID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        for constraint in sketch.constraints {
            try validateConstraintCanConvertLineToSpline(
                constraint,
                entityID: entityID,
                owner: owner
            )
        }
        for dimension in sketch.dimensions {
            try validateDimensionCanConvertLineToSpline(
                dimension,
                entityID: entityID,
                owner: owner
            )
        }
    }

    private func validateConstraintCanConvertLineToSpline(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        owner: String
    ) throws {
        switch constraint {
        case .coincident:
            return
        case .horizontal(let id),
             .vertical(let id):
            if id == entityID {
                throw lineSplineConversionError(owner, reason: "line orientation constraints")
            }
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second):
            if first == entityID || second == entityID {
                throw lineSplineConversionError(owner, reason: "line relationship constraints")
            }
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if first == entityID || second == entityID {
                throw lineSplineConversionError(owner, reason: "circular constraints")
            }
        case .smoothSplineControlPoint:
            return
        case .splineEndpointTangent:
            return
        case .tangentSplineEndpoints,
             .smoothSplineEndpoints:
            return
        case .fixed(let reference):
            if sketchReference(reference, references: entityID),
               isLineEndpointReference(reference, entityID: entityID) == false {
                throw lineSplineConversionError(owner, reason: "entity-level fixed constraints")
            }
        }
    }

    private func validateDimensionCanConvertLineToSpline(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        owner: String
    ) throws {
        switch dimension {
        case .distance(let first, let second, _),
             .angle(let first, let second, _):
            if sketchReference(first, references: entityID),
               isLineEndpointReference(first, entityID: entityID) == false {
                throw lineSplineConversionError(owner, reason: "entity-level dimensions")
            }
            if sketchReference(second, references: entityID),
               isLineEndpointReference(second, entityID: entityID) == false {
                throw lineSplineConversionError(owner, reason: "entity-level dimensions")
            }
        case .radius(let id, _),
             .diameter(let id, _):
            if id == entityID {
                throw lineSplineConversionError(owner, reason: "circular dimensions")
            }
        }
    }

    private func constraintsAfterLineToSplineConversion(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        originalSketch: Sketch,
        owner: String
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    rewriteLineEndpointToSplineReference(first, entityID: entityID),
                    rewriteLineEndpointToSplineReference(second, entityID: entityID)
                )
            case .fixed(let reference):
                return .fixed(
                    rewriteLineEndpointToSplineReference(reference, entityID: entityID)
                )
            case .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints:
                return constraint
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                guard lineID == entityID else {
                    return constraint
                }
                let source = SketchSplineEndpointReference(splineID: splineID, endpoint: endpoint)
                let convertedEndpoint = try convertedLineSplineEndpointForTangency(
                    source: source,
                    lineID: entityID,
                    constraints: constraints,
                    originalSketch: originalSketch,
                    owner: owner
                )
                return .tangentSplineEndpoints(
                    first: source,
                    second: SketchSplineEndpointReference(
                        splineID: entityID,
                        endpoint: convertedEndpoint
                    )
                )
            }
        }
    }

    private func dimensionsAfterLineToSplineConversion(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteLineEndpointToSplineReference(from, entityID: entityID),
                    to: rewriteLineEndpointToSplineReference(to, entityID: entityID),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteLineEndpointToSplineReference(from, entityID: entityID),
                    to: rewriteLineEndpointToSplineReference(to, entityID: entityID),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private struct SketchSplineControlPointInsertion {
        var spline: SketchSpline
        var originalControlPointCount: Int
        var segmentStartIndex: Int
        var segmentEndIndex: Int
        var insertedControlPointIndex: Int
    }

    private func insertedSplineControlPoint(
        in spline: SketchSpline,
        fraction: Double,
        owner: String
    ) throws -> SketchSplineControlPointInsertion {
        let controlPoints = spline.controlPoints
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let scaledParameter = fraction * Double(segmentCount)
        let segmentIndex = Int(floor(scaledParameter))
        let localFraction = scaledParameter - Double(segmentIndex)
        let tolerance = 1.0e-9
        guard localFraction > tolerance,
              localFraction < 1.0 - tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) fraction must resolve inside a cubic spline span, not on an existing knot."
            )
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let split = splitCubicBezier(
            p0,
            p1,
            p2,
            p3,
            fraction: .scalar(localFraction)
        )

        var next = Array(controlPoints[0 ... segmentStart])
        next.append(contentsOf: [
            split.left.1,
            split.left.2,
            split.left.3,
            split.right.1,
            split.right.2,
            split.right.3,
        ])
        if segmentStart + 4 < controlPoints.count {
            next.append(contentsOf: controlPoints[(segmentStart + 4)...])
        }

        let updatedSpline = SketchSpline(
            controlPoints: next,
            isClosed: spline.isClosed
        )
        try validateSpline(updatedSpline, owner: owner)
        return SketchSplineControlPointInsertion(
            spline: updatedSpline,
            originalControlPointCount: controlPoints.count,
            segmentStartIndex: segmentStart,
            segmentEndIndex: segmentStart + 3,
            insertedControlPointIndex: segmentStart + 3
        )
    }

    private func constraintsAfterSketchSplineControlPointInsertion(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        first,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        second,
                        entityID: entityID,
                        insertion: insertion
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        reference,
                        entityID: entityID,
                        insertion: insertion
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID else {
                    return constraint
                }
                return .smoothSplineControlPoint(
                    entity: id,
                    index: try rewriteSmoothSplineControlPointIndexAfterInsertion(
                        index,
                        insertion: insertion
                    )
                )
            case .splineEndpointTangent:
                return constraint
            case .tangentSplineEndpoints:
                return constraint
            case .smoothSplineEndpoints(let first, let second):
                guard splineEndpointHandleIsShortenedByInsertion(
                    first,
                    entityID: entityID,
                    insertion: insertion
                ) == false,
                    splineEndpointHandleIsShortenedByInsertion(
                        second,
                        entityID: entityID,
                        insertion: insertion
                    ) == false else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "smooth spline endpoint constraints"
                    )
                }
                return constraint
            case .horizontal(let id),
                 .vertical(let id):
                guard id != entityID else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "whole-spline orientation constraints"
                    )
                }
                return constraint
            case .parallel(let first, let second),
                 .perpendicular(let first, let second),
                 .equalLength(let first, let second),
                 .tangent(let first, let second),
                 .concentric(let first, let second),
                 .equalRadius(let first, let second):
                guard first != entityID && second != entityID else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "whole-spline relationship constraints"
                    )
                }
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchSplineControlPointInsertion(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        from,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    to: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        to,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        from,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    to: try rewriteSketchReferenceAfterSplineControlPointInsertion(
                        to,
                        entityID: entityID,
                        insertion: insertion
                    ),
                    value: value
                )
            case .radius(let id, _),
                 .diameter(let id, _):
                guard id != entityID else {
                    throw sketchSplineControlPointInsertionUnsupportedReference(
                        "circular dimensions"
                    )
                }
                return dimension
            }
        }
    }

    private func rewriteSketchReferenceAfterSplineControlPointInsertion(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) throws -> SketchReference {
        switch reference {
        case .splineControlPoint(let id, let index) where id == entityID:
            return .splineControlPoint(
                entity: id,
                index: try rewriteSplineControlPointIndexAfterInsertion(
                    index,
                    insertion: insertion
                )
            )
        case .splineControlPoint:
            return reference
        case .lineStart(let id),
             .lineEnd(let id),
             .entity(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id):
            guard id != entityID else {
                throw sketchSplineControlPointInsertionUnsupportedReference(
                    "incompatible point references"
                )
            }
            return reference
        }
    }

    private func rewriteSplineControlPointIndexAfterInsertion(
        _ index: Int,
        insertion: SketchSplineControlPointInsertion
    ) throws -> Int {
        if index == insertion.segmentStartIndex + 1 ||
            index == insertion.segmentStartIndex + 2 {
            throw sketchSplineControlPointInsertionUnsupportedReference(
                "references to replaced spline handles"
            )
        }
        if index >= insertion.segmentEndIndex {
            return index + 3
        }
        return index
    }

    private func rewriteSmoothSplineControlPointIndexAfterInsertion(
        _ index: Int,
        insertion: SketchSplineControlPointInsertion
    ) throws -> Int {
        if index == insertion.segmentStartIndex ||
            index == insertion.segmentEndIndex {
            throw sketchSplineControlPointInsertionUnsupportedReference(
                "smooth constraints on the insertion span boundary"
            )
        }
        return try rewriteSplineControlPointIndexAfterInsertion(
            index,
            insertion: insertion
        )
    }

    private func splineEndpointHandleIsShortenedByInsertion(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID,
        insertion: SketchSplineControlPointInsertion
    ) -> Bool {
        guard reference.splineID == entityID else {
            return false
        }
        switch reference.endpoint {
        case .start:
            return insertion.segmentStartIndex == 0
        case .end:
            return insertion.segmentEndIndex == insertion.originalControlPointCount - 1
        }
    }

    private func sketchSplineControlPointInsertionUnsupportedReference(
        _ reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch spline control point insertion cannot preserve \(reason) yet."
        )
    }

    private struct RebuiltSketchSpline {
        var spline: SketchSpline
        var originalControlPointCount: Int
        var rebuiltControlPointCount: Int
        var originalSegmentCount: Int
        var rebuiltSegmentCount: Int
        var deviation: SketchSplineRebuildDeviation
        var controlPointIndexMap: [Int: Int]

        var changesControlPointCount: Bool {
            originalControlPointCount != rebuiltControlPointCount
        }
    }

    private struct SketchSplineRebuildDeviation {
        var maximumDistance: Double
        var rootMeanSquareDistance: Double
        var maximumDistanceFraction: Double
        var evaluatedIntervalCount: Int
        var criticalPointCount: Int
    }

    private struct SketchSplineRebuildSample {
        var point: CADCore.Point2D
        var derivative: CADCore.Point2D
    }

    private enum SketchSplineRebuildSampleSide {
        case before
        case after
    }

    private struct SketchSplineRebuildInterval {
        var startFraction: Double
        var endFraction: Double
        var segmentCount: Int
    }

    private struct CubicBezierSegment2D {
        var p0: CADCore.Point2D
        var p1: CADCore.Point2D
        var p2: CADCore.Point2D
        var p3: CADCore.Point2D
    }

    private struct CubicSplineSegmentLocation {
        var segmentIndex: Int
        var localFraction: Double
    }

    private struct AnalyticCubicBezierDeviation {
        var maximumSquaredDistance: Double
        var maximumDistanceFraction: Double
        var squaredDistanceIntegral: Double
        var criticalPointCount: Int
    }

    private func curveRebuildReportMethod(
        for options: CurveRebuildOptions
    ) -> CurveRebuildReport.Method {
        switch options.method {
        case .points:
            return .points
        case .refit:
            return .refit
        case .explicitControl:
            return .explicitControl
        }
    }

    private func rebuiltSketchSplineByPointCount(
        _ spline: SketchSpline,
        controlPointCount: Int,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard controlPointCount >= 4,
              (controlPointCount - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Points method requires a 3n + 1 control point count of at least 4."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let rebuiltSegmentCount = (controlPointCount - 1) / 3
        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: rebuiltSegmentCount
                ),
            ],
            tangentWeight: 1.0,
            owner: owner
        )
    }

    private func rebuiltSketchSplineByRefit(
        _ spline: SketchSpline,
        tolerance: CADExpression,
        keepsCorners: Bool,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let toleranceMeters = try resolvedPositiveLengthValue(
            tolerance,
            owner: "\(owner) Refit tolerance"
        )
        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let intervals: [SketchSplineRebuildInterval]
        if keepsCorners {
            intervals = try refitIntervalsKeepingCorners(
                originalControlPoints,
                originalSegmentCount: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
        } else {
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: 0.0,
                endFraction: 1.0,
                originalSegmentSpan: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
            intervals = [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: segmentCount
                ),
            ]
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: intervals,
            tangentWeight: 1.0,
            owner: owner
        )
    }

    private func rebuiltSketchSplineByExplicitControl(
        _ spline: SketchSpline,
        degree: Int,
        spanCount: Int,
        weight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard degree == 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control currently supports degree 3 cubic Bezier output; degree \(degree) requires a B-spline/NURBS source model."
            )
        }
        guard spanCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control requires at least one span."
            )
        }
        guard weight.isFinite,
              weight >= 0.0,
              weight <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control weight must be between 0 and 1."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: spanCount
                ),
            ],
            tangentWeight: weight,
            owner: owner
        )
    }

    private func rebuiltSketchSpline(
        from spline: SketchSpline,
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        tangentWeight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = intervals.reduce(0) { $0 + $1.segmentCount }
        guard rebuiltSegmentCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires at least one rebuilt span."
            )
        }
        var rebuiltControlPoints: [SketchPoint] = []
        rebuiltControlPoints.reserveCapacity(rebuiltSegmentCount * 3 + 1)
        var indexMap: [Int: Int] = [:]

        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }

            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let handles = sketchSplineRebuildHandles(
                    start: start,
                    end: end,
                    span: span,
                    tangentWeight: tangentWeight
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(
                        sketchPoint(x: start.point.x, y: start.point.y)
                    )
                    mapOriginalKnotIfAligned(
                        fraction: startFraction,
                        originalSegmentCount: originalSegmentCount,
                        rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                        into: &indexMap
                    )
                }
                rebuiltControlPoints.append(sketchPoint(x: handles.first.x, y: handles.first.y))
                rebuiltControlPoints.append(sketchPoint(x: handles.second.x, y: handles.second.y))
                rebuiltControlPoints.append(sketchPoint(x: end.point.x, y: end.point.y))
                mapOriginalKnotIfAligned(
                    fraction: endFraction,
                    originalSegmentCount: originalSegmentCount,
                    rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                    into: &indexMap
                )
            }
        }

        let rebuiltSpline = SketchSpline(
            controlPoints: rebuiltControlPoints,
            isClosed: spline.isClosed
        )
        try validateSpline(rebuiltSpline, owner: owner)
        let rebuiltControlPointValues = try resolvedSplineControlPoints(
            rebuiltSpline,
            owner: owner
        )
        let deviation = try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPointValues,
            startFraction: 0.0,
            endFraction: 1.0
        )
        return RebuiltSketchSpline(
            spline: rebuiltSpline,
            originalControlPointCount: originalControlPoints.count,
            rebuiltControlPointCount: rebuiltControlPoints.count,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount,
            deviation: deviation,
            controlPointIndexMap: indexMap
        )
    }

    private func sketchSplineRebuildHandles(
        start: SketchSplineRebuildSample,
        end: SketchSplineRebuildSample,
        span: Double,
        tangentWeight: Double
    ) -> (first: CADCore.Point2D, second: CADCore.Point2D) {
        let chord = CADCore.Point2D(
            x: end.point.x - start.point.x,
            y: end.point.y - start.point.y
        )
        let chordFirst = CADCore.Point2D(
            x: start.point.x + chord.x / 3.0,
            y: start.point.y + chord.y / 3.0
        )
        let chordSecond = CADCore.Point2D(
            x: end.point.x - chord.x / 3.0,
            y: end.point.y - chord.y / 3.0
        )
        let tangentFirst = CADCore.Point2D(
            x: start.point.x + start.derivative.x * span / 3.0,
            y: start.point.y + start.derivative.y * span / 3.0
        )
        let tangentSecond = CADCore.Point2D(
            x: end.point.x - end.derivative.x * span / 3.0,
            y: end.point.y - end.derivative.y * span / 3.0
        )
        return (
            first: interpolate(
                from: chordFirst,
                to: tangentFirst,
                fraction: tangentWeight
            ),
            second: interpolate(
                from: chordSecond,
                to: tangentSecond,
                fraction: tangentWeight
            )
        )
    }

    private func interpolate(
        from first: CADCore.Point2D,
        to second: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        CADCore.Point2D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction
        )
    }

    private func refitIntervalsKeepingCorners(
        _ originalControlPoints: [CADCore.Point2D],
        originalSegmentCount: Int,
        tolerance: Double,
        owner: String
    ) throws -> [SketchSplineRebuildInterval] {
        let cornerBoundaries = cornerKnotSegmentBoundaries(
            originalControlPoints
        )
        var boundaries = [0]
        boundaries.append(contentsOf: cornerBoundaries)
        boundaries.append(originalSegmentCount)

        var intervals: [SketchSplineRebuildInterval] = []
        intervals.reserveCapacity(boundaries.count - 1)
        for index in 0 ..< boundaries.count - 1 {
            let startBoundary = boundaries[index]
            let endBoundary = boundaries[index + 1]
            let span = endBoundary - startBoundary
            guard span > 0 else {
                continue
            }
            let startFraction = Double(startBoundary) / Double(originalSegmentCount)
            let endFraction = Double(endBoundary) / Double(originalSegmentCount)
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: startFraction,
                endFraction: endFraction,
                originalSegmentSpan: span,
                tolerance: tolerance,
                owner: owner
            )
            intervals.append(
                SketchSplineRebuildInterval(
                    startFraction: startFraction,
                    endFraction: endFraction,
                    segmentCount: segmentCount
                )
            )
        }
        return intervals
    }

    private func refitSegmentCount(
        originalControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double,
        originalSegmentSpan: Int,
        tolerance: Double,
        owner: String
    ) throws -> Int {
        for segmentCount in 1 ... originalSegmentSpan {
            let candidateControlPoints = try rebuiltSketchSplineControlPoints(
                originalControlPoints: originalControlPoints,
                intervals: [
                    SketchSplineRebuildInterval(
                        startFraction: startFraction,
                        endFraction: endFraction,
                        segmentCount: segmentCount
                    ),
                ],
                owner: owner
            )
            let deviation = try maxSketchSplineDeviation(
                originalControlPoints: originalControlPoints,
                rebuiltControlPoints: candidateControlPoints,
                startFraction: startFraction,
                endFraction: endFraction
            )
            if deviation <= tolerance {
                return segmentCount
            }
        }
        return originalSegmentSpan
    }

    private func rebuiltSketchSplineControlPoints(
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        owner: String
    ) throws -> [CADCore.Point2D] {
        var rebuiltControlPoints: [CADCore.Point2D] = []
        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }
            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let firstHandle = CADCore.Point2D(
                    x: start.point.x + start.derivative.x * span / 3.0,
                    y: start.point.y + start.derivative.y * span / 3.0
                )
                let secondHandle = CADCore.Point2D(
                    x: end.point.x - end.derivative.x * span / 3.0,
                    y: end.point.y - end.derivative.y * span / 3.0
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(start.point)
                }
                rebuiltControlPoints.append(firstHandle)
                rebuiltControlPoints.append(secondHandle)
                rebuiltControlPoints.append(end.point)
            }
        }
        return rebuiltControlPoints
    }

    private func maxSketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> Double {
        try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPoints,
            startFraction: startFraction,
            endFraction: endFraction
        ).maximumDistance
    }

    private func sketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> SketchSplineRebuildDeviation {
        guard endFraction > startFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild generated an invalid deviation range."
            )
        }
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = (rebuiltControlPoints.count - 1) / 3
        let boundaries = sketchSplineDeviationBoundaries(
            startFraction: startFraction,
            endFraction: endFraction,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount
        )

        var maximumSquaredDistance = 0.0
        var maximumDistanceFraction = startFraction
        var squaredDistanceIntegral = 0.0
        var criticalPointCount = 0
        var evaluatedIntervalCount = 0

        for index in 0 ..< boundaries.count - 1 {
            let intervalStart = boundaries[index]
            let intervalEnd = boundaries[index + 1]
            guard intervalEnd > intervalStart + 1.0e-14 else {
                continue
            }
            let originalSegment = try cubicBezierSubcurve(
                controlPoints: originalControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let rebuiltSegment = try cubicBezierSubcurve(
                controlPoints: rebuiltControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let intervalDeviation = analyticCubicBezierDeviation(
                original: originalSegment,
                rebuilt: rebuiltSegment,
                globalStartFraction: intervalStart,
                globalEndFraction: intervalEnd
            )
            evaluatedIntervalCount += 1
            criticalPointCount += intervalDeviation.criticalPointCount
            squaredDistanceIntegral += intervalDeviation.squaredDistanceIntegral
            if intervalDeviation.maximumSquaredDistance > maximumSquaredDistance {
                maximumSquaredDistance = intervalDeviation.maximumSquaredDistance
                maximumDistanceFraction = intervalDeviation.maximumDistanceFraction
            }
        }
        let rangeLength = endFraction - startFraction
        let meanSquaredDistance = squaredDistanceIntegral / rangeLength
        return SketchSplineRebuildDeviation(
            maximumDistance: sqrt(max(0.0, maximumSquaredDistance)),
            rootMeanSquareDistance: sqrt(max(0.0, meanSquaredDistance)),
            maximumDistanceFraction: maximumDistanceFraction,
            evaluatedIntervalCount: evaluatedIntervalCount,
            criticalPointCount: criticalPointCount
        )
    }

    private func sketchSplineDeviationBoundaries(
        startFraction: Double,
        endFraction: Double,
        originalSegmentCount: Int,
        rebuiltSegmentCount: Int
    ) -> [Double] {
        var boundaries = [startFraction, endFraction]
        appendSplineSegmentBoundaries(
            segmentCount: originalSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        appendSplineSegmentBoundaries(
            segmentCount: rebuiltSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        return sortedUniqueFractions(boundaries)
    }

    private func appendSplineSegmentBoundaries(
        segmentCount: Int,
        startFraction: Double,
        endFraction: Double,
        to boundaries: inout [Double]
    ) {
        guard segmentCount > 1 else {
            return
        }
        for boundaryIndex in 1 ..< segmentCount {
            let boundary = Double(boundaryIndex) / Double(segmentCount)
            if boundary > startFraction + 1.0e-12,
               boundary < endFraction - 1.0e-12 {
                boundaries.append(boundary)
            }
        }
    }

    private func sortedUniqueFractions(_ fractions: [Double]) -> [Double] {
        var unique: [Double] = []
        for fraction in fractions.sorted() {
            if unique.last.map({ abs($0 - fraction) <= 1.0e-12 }) == true {
                continue
            }
            unique.append(fraction)
        }
        return unique
    }

    private func cubicBezierSubcurve(
        controlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> CubicBezierSegment2D {
        let start = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: startFraction,
            side: .after
        )
        let end = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: endFraction,
            side: .before
        )
        guard start.segmentIndex == end.segmentIndex,
              end.localFraction > start.localFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild deviation interval must stay inside one cubic span."
            )
        }

        let segmentStart = start.segmentIndex * 3
        var segment = CubicBezierSegment2D(
            p0: controlPoints[segmentStart],
            p1: controlPoints[segmentStart + 1],
            p2: controlPoints[segmentStart + 2],
            p3: controlPoints[segmentStart + 3]
        )
        if start.localFraction > 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: start.localFraction
            ).right
        }
        let remainingLength = 1.0 - start.localFraction
        let endInTrimmedSegment = (end.localFraction - start.localFraction) / remainingLength
        if endInTrimmedSegment < 1.0 - 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: endInTrimmedSegment
            ).left
        }
        return segment
    }

    private func cubicSplineSegmentLocation(
        controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> CubicSplineSegmentLocation {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild requires a cubic Bezier spline."
            )
        }

        let segmentCount = (controlPoints.count - 1) / 3
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let scaledFraction = clampedFraction * Double(segmentCount)
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            return CubicSplineSegmentLocation(segmentIndex: 0, localFraction: 0.0)
        }
        if scaledFraction >= Double(segmentCount) {
            return CubicSplineSegmentLocation(segmentIndex: segmentCount - 1, localFraction: 1.0)
        }
        if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                return CubicSplineSegmentLocation(
                    segmentIndex: max(0, boundary - 1),
                    localFraction: 1.0
                )
            case .after:
                return CubicSplineSegmentLocation(
                    segmentIndex: min(segmentCount - 1, boundary),
                    localFraction: 0.0
                )
            }
        }
        let segmentIndex = max(0, Int(floor(scaledFraction)))
        return CubicSplineSegmentLocation(
            segmentIndex: segmentIndex,
            localFraction: scaledFraction - Double(segmentIndex)
        )
    }

    private func splitCubicBezier(
        _ segment: CubicBezierSegment2D,
        fraction: Double
    ) -> (left: CubicBezierSegment2D, right: CubicBezierSegment2D) {
        let q0 = interpolate(from: segment.p0, to: segment.p1, fraction: fraction)
        let q1 = interpolate(from: segment.p1, to: segment.p2, fraction: fraction)
        let q2 = interpolate(from: segment.p2, to: segment.p3, fraction: fraction)
        let r0 = interpolate(from: q0, to: q1, fraction: fraction)
        let r1 = interpolate(from: q1, to: q2, fraction: fraction)
        let s = interpolate(from: r0, to: r1, fraction: fraction)
        return (
            left: CubicBezierSegment2D(p0: segment.p0, p1: q0, p2: r0, p3: s),
            right: CubicBezierSegment2D(p0: s, p1: r1, p2: q2, p3: segment.p3)
        )
    }

    private func analyticCubicBezierDeviation(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D,
        globalStartFraction: Double,
        globalEndFraction: Double
    ) -> AnalyticCubicBezierDeviation {
        let squaredDistance = squaredDistancePolynomial(
            original: original,
            rebuilt: rebuilt
        )
        let derivative = polynomialDerivative(squaredDistance)
        let roots = polynomialRootsInUnitInterval(derivative)
            .filter { $0 > 1.0e-10 && $0 < 1.0 - 1.0e-10 }
        let candidates = [0.0, 1.0] + roots
        var maximumSquaredDistance = 0.0
        var maximumLocalFraction = 0.0
        for candidate in candidates {
            let value = max(0.0, polynomialEvaluate(squaredDistance, at: candidate))
            if value > maximumSquaredDistance {
                maximumSquaredDistance = value
                maximumLocalFraction = candidate
            }
        }
        let intervalLength = globalEndFraction - globalStartFraction
        let squaredDistanceIntegral = intervalLength
            * max(0.0, polynomialUnitIntegral(squaredDistance))
        return AnalyticCubicBezierDeviation(
            maximumSquaredDistance: maximumSquaredDistance,
            maximumDistanceFraction: globalStartFraction
                + intervalLength * maximumLocalFraction,
            squaredDistanceIntegral: squaredDistanceIntegral,
            criticalPointCount: roots.count
        )
    }

    private func squaredDistancePolynomial(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D
    ) -> [Double] {
        let originalX = cubicBezierPowerCoefficients(
            original.p0.x,
            original.p1.x,
            original.p2.x,
            original.p3.x
        )
        let originalY = cubicBezierPowerCoefficients(
            original.p0.y,
            original.p1.y,
            original.p2.y,
            original.p3.y
        )
        let rebuiltX = cubicBezierPowerCoefficients(
            rebuilt.p0.x,
            rebuilt.p1.x,
            rebuilt.p2.x,
            rebuilt.p3.x
        )
        let rebuiltY = cubicBezierPowerCoefficients(
            rebuilt.p0.y,
            rebuilt.p1.y,
            rebuilt.p2.y,
            rebuilt.p3.y
        )
        let deltaX = zip(originalX, rebuiltX).map { $0 - $1 }
        let deltaY = zip(originalY, rebuiltY).map { $0 - $1 }
        return polynomialAdd(
            polynomialMultiply(deltaX, deltaX),
            polynomialMultiply(deltaY, deltaY)
        )
    }

    private func cubicBezierPowerCoefficients(
        _ p0: Double,
        _ p1: Double,
        _ p2: Double,
        _ p3: Double
    ) -> [Double] {
        [
            p0,
            -3.0 * p0 + 3.0 * p1,
            3.0 * p0 - 6.0 * p1 + 3.0 * p2,
            -p0 + 3.0 * p1 - 3.0 * p2 + p3,
        ]
    }

    private func polynomialAdd(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        let count = max(lhs.count, rhs.count)
        var result = Array(repeating: 0.0, count: count)
        for index in lhs.indices {
            result[index] += lhs[index]
        }
        for index in rhs.indices {
            result[index] += rhs[index]
        }
        return result
    }

    private func polynomialMultiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        guard lhs.isEmpty == false,
              rhs.isEmpty == false else {
            return []
        }
        var result = Array(repeating: 0.0, count: lhs.count + rhs.count - 1)
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
            }
        }
        return result
    }

    private func polynomialDerivative(_ coefficients: [Double]) -> [Double] {
        guard coefficients.count > 1 else {
            return [0.0]
        }
        return coefficients.dropFirst().enumerated().map { index, coefficient in
            coefficient * Double(index + 1)
        }
    }

    private func polynomialUnitIntegral(_ coefficients: [Double]) -> Double {
        coefficients.enumerated().reduce(0.0) { partial, element in
            partial + element.element / Double(element.offset + 1)
        }
    }

    private func polynomialEvaluate(
        _ coefficients: [Double],
        at fraction: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) { partial, coefficient in
            partial * fraction + coefficient
        }
    }

    private func polynomialRootsInUnitInterval(_ coefficients: [Double]) -> [Double] {
        let trimmed = trimmedPolynomial(coefficients)
        let degree = trimmed.count - 1
        guard degree > 0 else {
            return []
        }
        let valueTolerance = polynomialValueTolerance(trimmed)
        if degree == 1 {
            let root = -trimmed[0] / trimmed[1]
            guard root >= -1.0e-12,
                  root <= 1.0 + 1.0e-12 else {
                return []
            }
            return [min(max(root, 0.0), 1.0)]
        }

        let criticalPoints = polynomialRootsInUnitInterval(
            polynomialDerivative(trimmed)
        )
        let splitPoints = sortedUniqueFractions([0.0] + criticalPoints + [1.0])
        var roots: [Double] = []
        for point in splitPoints where abs(polynomialEvaluate(trimmed, at: point)) <= valueTolerance {
            roots.append(point)
        }
        for index in 0 ..< splitPoints.count - 1 {
            let start = splitPoints[index]
            let end = splitPoints[index + 1]
            guard end > start + 1.0e-12 else {
                continue
            }
            let startValue = polynomialEvaluate(trimmed, at: start)
            let endValue = polynomialEvaluate(trimmed, at: end)
            if startValue * endValue < 0.0 {
                roots.append(
                    bisectedPolynomialRoot(
                        trimmed,
                        lower: start,
                        upper: end,
                        lowerValue: startValue,
                        tolerance: valueTolerance
                    )
                )
            }
        }
        return sortedUniqueFractions(
            roots.map { min(max($0, 0.0), 1.0) }
        )
    }

    private func bisectedPolynomialRoot(
        _ coefficients: [Double],
        lower: Double,
        upper: Double,
        lowerValue: Double,
        tolerance: Double
    ) -> Double {
        var low = lower
        var high = upper
        var lowValue = lowerValue
        for _ in 0 ..< 80 {
            let mid = (low + high) * 0.5
            let midValue = polynomialEvaluate(coefficients, at: mid)
            if abs(midValue) <= tolerance || high - low <= 1.0e-13 {
                return mid
            }
            if lowValue * midValue <= 0.0 {
                high = mid
            } else {
                low = mid
                lowValue = midValue
            }
        }
        return (low + high) * 0.5
    }

    private func trimmedPolynomial(_ coefficients: [Double]) -> [Double] {
        var trimmed = coefficients
        let tolerance = polynomialValueTolerance(coefficients)
        while trimmed.count > 1,
              abs(trimmed.last ?? 0.0) <= tolerance {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func polynomialValueTolerance(_ coefficients: [Double]) -> Double {
        max(1.0e-24, (coefficients.map { abs($0) }.max() ?? 0.0) * 1.0e-12)
    }

    private func cornerKnotSegmentBoundaries(
        _ controlPoints: [CADCore.Point2D]
    ) -> [Int] {
        let segmentCount = (controlPoints.count - 1) / 3
        guard segmentCount > 1 else {
            return []
        }

        var boundaries: [Int] = []
        for segmentBoundary in 1 ..< segmentCount {
            let knotIndex = segmentBoundary * 3
            let incoming = CADCore.Point2D(
                x: controlPoints[knotIndex].x - controlPoints[knotIndex - 1].x,
                y: controlPoints[knotIndex].y - controlPoints[knotIndex - 1].y
            )
            let outgoing = CADCore.Point2D(
                x: controlPoints[knotIndex + 1].x - controlPoints[knotIndex].x,
                y: controlPoints[knotIndex + 1].y - controlPoints[knotIndex].y
            )
            if isCornerBetweenSplineHandles(incoming: incoming, outgoing: outgoing) {
                boundaries.append(segmentBoundary)
            }
        }
        return boundaries
    }

    private func isCornerBetweenSplineHandles(
        incoming: CADCore.Point2D,
        outgoing: CADCore.Point2D
    ) -> Bool {
        let incomingLength = vectorLength(incoming)
        let outgoingLength = vectorLength(outgoing)
        let tinyLength = 1.0e-12
        guard incomingLength > tinyLength,
              outgoingLength > tinyLength else {
            return true
        }
        let dot = (incoming.x * outgoing.x + incoming.y * outgoing.y)
            / (incomingLength * outgoingLength)
        let clampedDot = min(max(dot, -1.0), 1.0)
        return clampedDot < cos(1.0e-4)
    }

    private func distance(
        _ first: CADCore.Point2D,
        _ second: CADCore.Point2D
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }

    private func vectorLength(_ vector: CADCore.Point2D) -> Double {
        sqrt(vector.x * vector.x + vector.y * vector.y)
    }

    private func mapOriginalKnotIfAligned(
        fraction: Double,
        originalSegmentCount: Int,
        rebuiltControlPointIndex: Int,
        into indexMap: inout [Int: Int]
    ) {
        let scaled = fraction * Double(originalSegmentCount)
        let rounded = scaled.rounded()
        guard abs(scaled - rounded) <= 1.0e-9 else {
            return
        }
        let segmentBoundary = Int(rounded)
        guard segmentBoundary >= 0,
              segmentBoundary <= originalSegmentCount else {
            return
        }
        indexMap[segmentBoundary * 3] = rebuiltControlPointIndex
    }

    private func resolvedSplineControlPoints(
        _ spline: SketchSpline,
        owner: String
    ) throws -> [CADCore.Point2D] {
        try spline.controlPoints.enumerated().map { index, point in
            let resolved = try resolvedPoint(
                point,
                owner: "\(owner) control point \(index + 1)"
            )
            return CADCore.Point2D(x: resolved.x, y: resolved.y)
        }
    }

    private func sketchSplineRebuildSample(
        on controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> SketchSplineRebuildSample {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild requires a cubic Bezier spline."
            )
        }

        let segmentCount = (controlPoints.count - 1) / 3
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let scaledFraction = clampedFraction * Double(segmentCount)
        let segmentIndex: Int
        let localFraction: Double
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            segmentIndex = 0
            localFraction = 0.0
        } else if scaledFraction >= Double(segmentCount) {
            segmentIndex = segmentCount - 1
            localFraction = 1.0
        } else if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                segmentIndex = max(0, boundary - 1)
                localFraction = 1.0
            case .after:
                segmentIndex = min(segmentCount - 1, boundary)
                localFraction = 0.0
            }
        } else {
            segmentIndex = max(0, Int(floor(scaledFraction)))
            localFraction = scaledFraction - Double(segmentIndex)
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let localDerivative = cubicBezierDerivative(
            p0,
            p1,
            p2,
            p3,
            fraction: localFraction
        )
        return SketchSplineRebuildSample(
            point: cubicBezierPoint(
                p0,
                p1,
                p2,
                p3,
                fraction: localFraction
            ),
            derivative: CADCore.Point2D(
                x: localDerivative.x * Double(segmentCount),
                y: localDerivative.y * Double(segmentCount)
            )
        )
    }

    private func cubicBezierPoint(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        let inverseSquared = inverse * inverse
        let fractionSquared = fraction * fraction
        let inverseCubed = inverseSquared * inverse
        let fractionCubed = fractionSquared * fraction
        return CADCore.Point2D(
            x: inverseCubed * p0.x
                + 3.0 * inverseSquared * fraction * p1.x
                + 3.0 * inverse * fractionSquared * p2.x
                + fractionCubed * p3.x,
            y: inverseCubed * p0.y
                + 3.0 * inverseSquared * fraction * p1.y
                + 3.0 * inverse * fractionSquared * p2.y
                + fractionCubed * p3.y
        )
    }

    private func cubicBezierDerivative(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        return CADCore.Point2D(
            x: 3.0 * inverse * inverse * (p1.x - p0.x)
                + 6.0 * inverse * fraction * (p2.x - p1.x)
                + 3.0 * fraction * fraction * (p3.x - p2.x),
            y: 3.0 * inverse * inverse * (p1.y - p0.y)
                + 6.0 * inverse * fraction * (p2.y - p1.y)
                + 3.0 * fraction * fraction * (p3.y - p2.y)
        )
    }

    private func constraintsAfterSketchCurveRebuild(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        first,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    try rewriteSketchReferenceAfterCurveRebuild(
                        second,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID else {
                    return constraint
                }
                if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                    return .smoothSplineControlPoint(entity: id, index: rebuiltIndex)
                }
                guard rebuilt.changesControlPointCount == false else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "internal smooth spline constraints when the point count changes"
                    )
                }
                return .smoothSplineControlPoint(entity: id, index: index)
            case .splineEndpointTangent:
                return constraint
            case .tangentSplineEndpoints:
                return constraint
            case .smoothSplineEndpoints(let first, let second):
                guard rebuilt.changesControlPointCount == false ||
                    (first.splineID != entityID && second.splineID != entityID) else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "smooth spline endpoint constraints when the point count changes"
                    )
                }
                return constraint
            case .horizontal(let id),
                 .vertical(let id):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline orientation constraints"
                    )
                }
                return constraint
            case .parallel(let first, let second),
                 .perpendicular(let first, let second),
                 .equalLength(let first, let second),
                 .tangent(let first, let second),
                 .concentric(let first, let second),
                 .equalRadius(let first, let second):
                guard first != entityID && second != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline relationship constraints"
                    )
                }
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchCurveRebuild(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .radius(let id, _),
                 .diameter(let id, _):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "circular dimensions"
                    )
                }
                return dimension
            }
        }
    }

    private func bridgeCurveSourcesAfterSketchCurveRebuild(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [BridgeCurveSourceID: BridgeCurveSource] {
        var updated: [BridgeCurveSourceID: BridgeCurveSource] = [:]
        updated.reserveCapacity(sources.count)
        for (id, source) in sources {
            guard source.featureID != featureID || source.entityID != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "generated Bridge Curve source entities"
                )
            }
            updated[id] = BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.firstEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.firstEndpoint.parameter,
                    reversesSense: source.firstEndpoint.reversesSense,
                    tension: source.firstEndpoint.tension
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.secondEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.secondEndpoint.parameter,
                    reversesSense: source.secondEndpoint.reversesSense,
                    tension: source.secondEndpoint.tension
                ),
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
        return updated
    }

    private func rewriteSketchReferenceAfterCurveRebuild(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> SketchReference {
        switch reference {
        case .splineControlPoint(let id, let index) where id == entityID:
            guard index >= 0,
                  index < rebuilt.originalControlPointCount else {
                throw sketchCurveRebuildUnsupportedReference(
                    "out-of-range spline control-point references"
                )
            }
            if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                return .splineControlPoint(
                    entity: entityID,
                    index: rebuiltIndex
                )
            }
            guard rebuilt.changesControlPointCount == false else {
                throw sketchCurveRebuildUnsupportedReference(
                    "internal spline control-point references when the point count changes"
                )
            }
            return reference
        case .splineControlPoint:
            return reference
        case .lineStart(let id),
             .lineEnd(let id),
             .entity(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id):
            guard id != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "incompatible point references"
                )
            }
            return reference
        }
    }

    private func sketchCurveRebuildUnsupportedReference(
        _ reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch curve rebuild cannot preserve \(reason) yet."
        )
    }

    private func constraintsAfterSketchCurveReverse(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [SketchConstraint] {
        constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    rewriteSketchReferenceAfterCurveReverse(
                        first,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    rewriteSketchReferenceAfterCurveReverse(
                        second,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    rewriteSketchReferenceAfterCurveReverse(
                        reference,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID,
                      let count = splineControlPointCount else {
                    return constraint
                }
                return .smoothSplineControlPoint(
                    entity: entityID,
                    index: reversedSplineControlPointIndex(index, controlPointCount: count)
                )
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                guard splineID == entityID else {
                    return constraint
                }
                return .splineEndpointTangent(
                    spline: splineID,
                    endpoint: reversedSplineEndpoint(endpoint),
                    line: lineID
                )
            case .tangentSplineEndpoints(let first, let second):
                return .tangentSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        second,
                        entityID: entityID
                    )
                )
            case .smoothSplineEndpoints(let first, let second):
                return .smoothSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        second,
                        entityID: entityID
                    )
                )
            case .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius:
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchCurveReverse(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteSketchReferenceAfterCurveReverse(
                        from,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    to: rewriteSketchReferenceAfterCurveReverse(
                        to,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteSketchReferenceAfterCurveReverse(
                        from,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    to: rewriteSketchReferenceAfterCurveReverse(
                        to,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private struct SketchCurveSegmentSplitResult {
        var originalEntityID: SketchEntityID
        var newEntityID: SketchEntityID
        var fraction: Double
        var retainedEntity: SketchEntity
        var newEntity: SketchEntity
        var insertedRetainedReference: SketchReference
        var insertedNewReference: SketchReference
        var originalEndReference: SketchReference
        var migratedEndReference: SketchReference
    }

    private func validateSketchCurveCanSplit(
        selection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        )
    ) throws {
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split cannot split a generated Bridge Curve source."
            )
        }

        switch selection.entity {
        case .line:
            break
        case .spline(let spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve split requires an open spline curve."
                )
            }
        case .arc:
            break
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split requires an open line, arc, or spline curve; circles do not expose a split segment."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split requires a line, arc, or spline curve target."
            )
        }

        for constraint in selection.sketch.constraints {
            try validateConstraintCanSplitSketchCurve(
                constraint,
                entityID: selection.entityID,
                entity: selection.entity
            )
        }
        for dimension in selection.sketch.dimensions {
            try validateDimensionCanSplitSketchCurve(
                dimension,
                entityID: selection.entityID,
                entity: selection.entity
            )
        }
    }

    private func validateConstraintCanSplitSketchCurve(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        switch constraint {
        case .coincident(let first, let second):
            try validateSketchReferenceCanSplit(first, entityID: entityID, entity: entity)
            try validateSketchReferenceCanSplit(second, entityID: entityID, entity: entity)
        case .fixed(let reference):
            try validateSketchReferenceCanSplit(reference, entityID: entityID, entity: entity)
        case .horizontal(let id),
             .vertical(let id):
            if id == entityID, case .spline = entity {
                throw sketchCurveSplitUnsupportedConstraint("spline orientation constraints")
            }
        case .parallel(let first, let second),
             .perpendicular(let first, let second):
            if first == entityID || second == entityID,
               case .spline = entity {
                throw sketchCurveSplitUnsupportedConstraint("spline line relationship constraints")
            }
        case .equalLength(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("equal-length constraints")
            }
        case .tangent(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("curve tangent constraints")
            }
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("circular constraints")
            }
        case .smoothSplineControlPoint(let id, _):
            if id == entityID {
                throw sketchCurveSplitUnsupportedConstraint("internal spline smooth constraints")
            }
        case .splineEndpointTangent:
            return
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            try validateSplineEndpointReferenceCanSplit(first, entityID: entityID, entity: entity)
            try validateSplineEndpointReferenceCanSplit(second, entityID: entityID, entity: entity)
        }
    }

    private func validateDimensionCanSplitSketchCurve(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            try validateSketchReferenceCanSplit(from, entityID: entityID, entity: entity)
            try validateSketchReferenceCanSplit(to, entityID: entityID, entity: entity)
        case .radius(let id, _),
             .diameter(let id, _):
            if id == entityID {
                throw sketchCurveSplitUnsupportedConstraint("circular dimensions")
            }
        }
    }

    private func validateSketchReferenceCanSplit(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        guard sketchReference(reference, references: entityID) else {
            return
        }
        switch (reference, entity) {
        case (.lineStart(let id), .line) where id == entityID:
            return
        case (.lineEnd(let id), .line) where id == entityID:
            return
        case (.arcStart(let id), .arc) where id == entityID:
            return
        case (.arcEnd(let id), .arc) where id == entityID:
            return
        case (.splineControlPoint(let id, let index), .spline(let spline)) where id == entityID:
            guard index == 0 || index == spline.controlPoints.count - 1 else {
                throw sketchCurveSplitUnsupportedConstraint("internal spline control-point references")
            }
        default:
            throw sketchCurveSplitUnsupportedConstraint("entity-level or incompatible references")
        }
    }

    private func validateSplineEndpointReferenceCanSplit(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        guard reference.splineID == entityID else {
            return
        }
        guard case .spline = entity else {
            throw sketchCurveSplitUnsupportedConstraint("incompatible spline endpoint references")
        }
    }

    private func sketchCurveSplitUnsupportedConstraint(_ reason: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch curve split cannot preserve \(reason) yet."
        )
    }

    private func validateSketchCurveSegmentCanTrim(
        selection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        )
    ) throws {
        switch selection.entity {
        case .line,
             .arc:
            break
        case .spline(let spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve trim requires an open spline segment."
                )
            }
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve trim requires a bounded curve segment; circles do not expose segment boundaries."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve trim requires a curve segment target."
            )
        }

        for source in productMetadata.bridgeCurveSources.values where source.featureID == selection.featureID {
            if source.entityID == selection.entityID {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve trim cannot remove a generated Bridge Curve source."
                )
            }
            if sketchReference(source.firstEndpoint.reference, references: selection.entityID) ||
                sketchReference(source.secondEndpoint.reference, references: selection.entityID) {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve trim cannot remove a segment used by Bridge Curve metadata."
                )
            }
        }
    }

    private func constraintsAfterSketchCurveTrim(
        _ constraints: [SketchConstraint],
        trimmedEntityID: SketchEntityID
    ) -> [SketchConstraint] {
        constraints.filter { constraint in
            sketchConstraint(constraint, references: trimmedEntityID) == false
        }
    }

    private func dimensionsAfterSketchCurveTrim(
        _ dimensions: [SketchDimension],
        trimmedEntityID: SketchEntityID
    ) -> [SketchDimension] {
        dimensions.filter { dimension in
            sketchDimension(dimension, references: trimmedEntityID) == false
        }
    }

    private func sketchConstraint(
        _ constraint: SketchConstraint,
        references entityID: SketchEntityID
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return sketchReference(first, references: entityID) ||
                sketchReference(second, references: entityID)
        case .fixed(let reference):
            return sketchReference(reference, references: entityID)
        case .horizontal(let id),
             .vertical(let id),
             .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return first == entityID || second == entityID
        case .splineEndpointTangent(let splineID, _, let lineID):
            return splineID == entityID || lineID == entityID
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return first.splineID == entityID || second.splineID == entityID
        }
    }

    private func sketchDimension(
        _ dimension: SketchDimension,
        references entityID: SketchEntityID
    ) -> Bool {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            return sketchReference(from, references: entityID) ||
                sketchReference(to, references: entityID)
        case .radius(let id, _),
             .diameter(let id, _):
            return id == entityID
        }
    }

    private struct CutCurveLineSegment {
        var startX: Double
        var startY: Double
        var endX: Double
        var endY: Double
    }

    private struct CutCurveCircle {
        var centerX: Double
        var centerY: Double
        var radius: Double
    }

    private struct CutCurveArc {
        var circle: CutCurveCircle
        var startAngle: Double
        var endAngle: Double
    }

    private func cutSketchCurveFractions(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws -> [Double] {
        try validateCutSketchCurveSelections(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        let fractions: [Double]
        switch targetSelection.entity {
        case .line(let targetLine):
            let target = try resolvedCutCurveLineSegment(targetLine, owner: "Cut Curve target")
            fractions = try cutFractionsForLineTarget(
                target: target,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .arc(let targetArc):
            let target = try resolvedCutCurveArc(targetArc, owner: "Cut Curve target")
            fractions = try cutFractionsForArcTarget(
                target: target,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .point, .circle, .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line or arc target curve."
            )
        }
        let uniqueFractions = uniqueInteriorCutFractions(fractions)
        guard uniqueFractions.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not intersect the target curve inside the supported target segment."
            )
        }
        return uniqueFractions
    }

    private func cutFractionsForLineTarget(
        target: CutCurveLineSegment,
        cutterSelection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        ),
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            return try cutFractionsForLineLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return cutFractionsForLineCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve arc cutter extension is not represented in the current source subset."
                )
            }
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return cutFractionsForLineCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: cutter
            )
        case .point, .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, or arc cutter curve."
            )
        }
    }

    private mutating func cutSketchCircleTarget(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [SketchEntityID] {
        try validateCutSketchCurveSelections(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        guard case .circle(let targetCircleEntity) = targetSelection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target requires a source circle target."
            )
        }
        try validateSketchCircleCanCut(selection: targetSelection)
        let targetCircle = try resolvedCutCurveCircle(
            targetCircleEntity,
            owner: "Cut Curve target"
        )
        let angles = try cutAnglesForCircleTarget(
            target: targetCircle,
            cutterSelection: cutterSelection,
            extendsCutter: options.extendsCutter
        )

        let retainedArc = SketchArc(
            center: targetCircleEntity.center,
            radius: targetCircleEntity.radius,
            startAngle: .angle(angles[0], .radian),
            endAngle: .angle(angles[1], .radian)
        )
        let newArc = SketchArc(
            center: targetCircleEntity.center,
            radius: targetCircleEntity.radius,
            startAngle: .angle(angles[1], .radian),
            endAngle: .angle(angles[0], .radian)
        )
        try validateArc(retainedArc, owner: "Cut Curve retained circle arc")
        try validateArc(newArc, owner: "Cut Curve new circle arc")

        let newEntityID = SketchEntityID()
        var feature = targetSelection.feature
        var sketch = targetSelection.sketch
        sketch.entities[targetSelection.entityID] = .arc(retainedArc)
        sketch.entities[newEntityID] = .arc(newArc)
        sketch.constraints.append(.coincident(.arcEnd(targetSelection.entityID), .arcStart(newEntityID)))
        sketch.constraints.append(.coincident(.arcEnd(newEntityID), .arcStart(targetSelection.entityID)))

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitCut = false
        defer {
            if didCommitCut == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if targetSelection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: targetSelection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: targetSelection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Cut Curve"
        )
        didCommitCut = true
        return [newEntityID]
    }

    private func validateCutSketchCurveSelections(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws {
        guard options.usesScreenSpaceDirection == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve screen-space direction requires a 3D cutter context that is not represented yet."
            )
        }
        guard targetSelection.featureID != cutterSelection.featureID ||
            targetSelection.entityID != cutterSelection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve requires distinct target and cutter curves."
            )
        }
        guard targetSelection.sketch.plane == cutterSelection.sketch.plane else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source curve cutter requires target and cutter to share a sketch plane."
            )
        }
    }

    private func validateSketchCircleCanCut(
        selection: EditableSketchEntitySelection
    ) throws {
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cannot cut a generated Bridge Curve source."
            )
        }
        let affectedEntityIDs: Set<SketchEntityID> = [selection.entityID]
        for dimension in selection.sketch.dimensions where dimensionReferencesAny(
            dimension,
            entityIDs: affectedEntityIDs
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target cannot preserve dimensions attached to the circle yet."
            )
        }
        for constraint in selection.sketch.constraints where constraintReferencesAny(
            constraint,
            entityIDs: affectedEntityIDs
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target cannot preserve constraints attached to the circle yet."
            )
        }
    }

    private func cutAnglesForCircleTarget(
        target: CutCurveCircle,
        cutterSelection: EditableSketchEntitySelection,
        extendsCutter: Bool
    ) throws -> [Double] {
        let angles: [Double]
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve arc cutter extension is not represented in the current source subset."
                )
            }
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: cutter
            )
        case .point, .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, or arc cutter curve."
            )
        }
        let uniqueAngles = uniqueCutAngles(angles)
        guard uniqueAngles.count == 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target requires two distinct cutter intersections to create two arc segments."
            )
        }
        return uniqueAngles
    }

    private func cutFractionsForArcTarget(
        target: CutCurveArc,
        cutterSelection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        ),
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            return try cutFractionsForArcLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return try cutFractionsForArcCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve arc cutter extension is not represented in the current source subset."
                )
            }
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return try cutFractionsForArcCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: cutter
            )
        case .point, .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, or arc cutter curve."
            )
        }
    }

    private func resolvedCutCurveLineSegment(
        _ line: SketchLine,
        owner: String
    ) throws -> CutCurveLineSegment {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        guard hypot(deltaX, deltaY) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) length must be greater than zero."
            )
        }
        return CutCurveLineSegment(
            startX: startX,
            startY: startY,
            endX: endX,
            endY: endY
        )
    }

    private func resolvedCutCurveCircle(
        _ circle: SketchCircle,
        owner: String
    ) throws -> CutCurveCircle {
        let centerX = try resolvedLengthValue(circle.center.x, owner: "\(owner) center x")
        let centerY = try resolvedLengthValue(circle.center.y, owner: "\(owner) center y")
        let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) radius")
        return CutCurveCircle(centerX: centerX, centerY: centerY, radius: radius)
    }

    private func resolvedCutCurveArc(
        _ arc: SketchArc,
        owner: String
    ) throws -> CutCurveArc {
        let circle = try resolvedCutCurveCircle(
            SketchCircle(center: arc.center, radius: arc.radius),
            owner: owner
        )
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        return CutCurveArc(circle: circle, startAngle: startAngle, endAngle: endAngle)
    }

    private func cutFractionsForLineLineIntersection(
        target: CutCurveLineSegment,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let denominator = targetX * cutterY - targetY * cutterX
        guard abs(denominator) > 1.0e-14 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve line cutter must intersect the target line; parallel or overlapping lines are unsupported."
            )
        }

        let deltaX = cutter.startX - target.startX
        let deltaY = cutter.startY - target.startY
        let targetFraction = (deltaX * cutterY - deltaY * cutterX) / denominator
        let cutterFraction = (deltaX * targetY - deltaY * targetX) / denominator
        let tolerance = 1.0e-10
        guard targetFraction > tolerance,
              targetFraction < 1.0 - tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve intersection must fall inside the target curve segment, not on its endpoint."
            )
        }
        if extendsCutter == false {
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
                )
            }
        }
        return [targetFraction]
    }

    private func cutFractionsForLineCircleIntersection(
        target: CutCurveLineSegment,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let lengthSquared = targetX * targetX + targetY * targetY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = target.startX - circle.centerX
        let offsetY = target.startY - circle.centerY
        let b = 2.0 * (offsetX * targetX + offsetY * targetY)
        let c = offsetX * offsetX + offsetY * offsetY - circle.radius * circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return rawFractions.filter { fraction in
            guard fraction > tolerance,
                  fraction < 1.0 - tolerance else {
                return false
            }
            guard let arc else {
                return true
            }
            let pointX = target.startX + targetX * fraction
            let pointY = target.startY + targetY * fraction
            let angle = atan2(pointY - arc.circle.centerY, pointX - arc.circle.centerX)
            return cutCurveAngleIsOnArc(angle, startAngle: arc.startAngle, endAngle: arc.endAngle)
        }
    }

    private func cutFractionsForArcLineIntersection(
        target: CutCurveArc,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.circle.centerX
        let offsetY = cutter.startY - target.circle.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.circle.radius * target.circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let targetFractions = rawCutterFractions.compactMap { cutterFraction -> Double? in
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            let angle = atan2(pointY - target.circle.centerY, pointX - target.circle.centerX)
            guard cutCurveAngleIsOnArc(
                angle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            return cutCurveArcFraction(for: angle, on: target)
        }
        if targetFractions.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return targetFractions
    }

    private func cutFractionsForArcCircleIntersection(
        target: CutCurveArc,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target.circle,
            circle
        )
        return points.compactMap { point -> Double? in
            let targetAngle = atan2(
                point.y - target.circle.centerY,
                point.x - target.circle.centerX
            )
            guard cutCurveAngleIsOnArc(
                targetAngle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return cutCurveArcFraction(for: targetAngle, on: target)
        }
    }

    private func cutAnglesForCircleLineIntersection(
        target: CutCurveCircle,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.centerX
        let offsetY = cutter.startY - target.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.radius * target.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let angles = rawCutterFractions.compactMap { cutterFraction -> Double? in
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            return atan2(pointY - target.centerY, pointX - target.centerX)
        }
        if angles.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return angles
    }

    private func cutAnglesForCircleCircleIntersection(
        target: CutCurveCircle,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target,
            circle
        )
        return points.compactMap { point -> Double? in
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return atan2(point.y - target.centerY, point.x - target.centerX)
        }
    }

    private func cutCurveCircleCircleIntersections(
        _ first: CutCurveCircle,
        _ second: CutCurveCircle
    ) throws -> [(x: Double, y: Double)] {
        let deltaX = second.centerX - first.centerX
        let deltaY = second.centerY - first.centerY
        let distance = hypot(deltaX, deltaY)
        let tolerance = 1.0e-10
        guard distance > tolerance else {
            if abs(first.radius - second.radius) <= tolerance {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve coincident circular curves do not create discrete intersections in the current source subset."
                )
            }
            return []
        }
        guard distance <= first.radius + second.radius + tolerance,
              distance >= abs(first.radius - second.radius) - tolerance else {
            return []
        }

        let firstRadiusSquared = first.radius * first.radius
        let secondRadiusSquared = second.radius * second.radius
        let distanceSquared = distance * distance
        let centerOffset = (firstRadiusSquared - secondRadiusSquared + distanceSquared) /
            (2.0 * distance)
        let heightSquared = firstRadiusSquared - centerOffset * centerOffset
        guard heightSquared >= -1.0e-14 else {
            return []
        }

        let unitX = deltaX / distance
        let unitY = deltaY / distance
        let baseX = first.centerX + centerOffset * unitX
        let baseY = first.centerY + centerOffset * unitY
        let height = sqrt(max(heightSquared, 0.0))
        if height <= tolerance {
            return [(x: baseX, y: baseY)]
        }
        let perpendicularX = -unitY * height
        let perpendicularY = unitX * height
        return [
            (x: baseX + perpendicularX, y: baseY + perpendicularY),
            (x: baseX - perpendicularX, y: baseY - perpendicularY),
        ]
    }

    private func uniqueInteriorCutFractions(_ fractions: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        return fractions
            .filter { fraction in
                fraction > tolerance && fraction < 1.0 - tolerance
            }
            .sorted()
            .reduce(into: [Double]()) { uniqueFractions, fraction in
                guard uniqueFractions.contains(where: { abs($0 - fraction) <= tolerance }) == false else {
                    return
                }
                uniqueFractions.append(fraction)
            }
    }

    private func uniqueCutAngles(_ angles: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        let fullCircle = Double.pi * 2.0
        var uniqueAngles = angles
            .map(normalizedCutAngle)
            .sorted()
            .reduce(into: [Double]()) { uniqueAngles, angle in
                guard uniqueAngles.contains(where: { abs($0 - angle) <= tolerance }) == false else {
                    return
                }
                uniqueAngles.append(angle)
            }
        if let first = uniqueAngles.first,
           let last = uniqueAngles.last,
           uniqueAngles.count > 1,
           fullCircle - last + first <= tolerance {
            uniqueAngles.removeLast()
        }
        return uniqueAngles
    }

    private func normalizedCutAngle(_ angle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var normalized = angle
        while normalized < 0.0 {
            normalized += fullCircle
        }
        while normalized >= fullCircle {
            normalized -= fullCircle
        }
        if fullCircle - normalized <= 1.0e-10 {
            return 0.0
        }
        return normalized
    }

    private func cutCurveAngleIsOnArc(
        _ angle: Double,
        startAngle: Double,
        endAngle: Double
    ) -> Bool {
        normalizedAngleDelta(from: startAngle, to: angle) <=
            positiveArcSpan(startAngle: startAngle, endAngle: endAngle) + 1.0e-10
    }

    private func cutCurveArcFraction(
        for angle: Double,
        on arc: CutCurveArc
    ) -> Double {
        normalizedAngleDelta(from: arc.startAngle, to: angle) /
            positiveArcSpan(startAngle: arc.startAngle, endAngle: arc.endAngle)
    }

    private func normalizedAngleDelta(
        from startAngle: Double,
        to angle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = angle - startAngle
        while delta < 0.0 {
            delta += fullCircle
        }
        while delta >= fullCircle {
            delta -= fullCircle
        }
        return delta
    }

    private func splitSketchCurveEntity(
        _ entity: SketchEntity,
        entityID: SketchEntityID,
        newEntityID: SketchEntityID,
        fraction: Double,
        owner: String
    ) throws -> SketchCurveSegmentSplitResult {
        switch entity {
        case .line(let line):
            let splitPoint = try splitPoint(on: line, fraction: fraction, owner: owner)
            let retainedLine = SketchLine(start: line.start, end: splitPoint)
            let newLine = SketchLine(start: splitPoint, end: line.end)
            _ = try resolvedLineMetrics(retainedLine, owner: owner)
            _ = try resolvedLineMetrics(newLine, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .line(retainedLine),
                newEntity: .line(newLine),
                insertedRetainedReference: .lineEnd(entityID),
                insertedNewReference: .lineStart(newEntityID),
                originalEndReference: .lineEnd(entityID),
                migratedEndReference: .lineEnd(newEntityID)
            )
        case .spline(let spline):
            let split = try splitSpline(
                spline,
                fraction: fraction,
                owner: owner
            )
            try validateSpline(split.retained, owner: owner)
            try validateSpline(split.new, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .spline(split.retained),
                newEntity: .spline(split.new),
                insertedRetainedReference: .splineControlPoint(
                    entity: entityID,
                    index: split.retained.controlPoints.count - 1
                ),
                insertedNewReference: .splineControlPoint(entity: newEntityID, index: 0),
                originalEndReference: .splineControlPoint(
                    entity: entityID,
                    index: spline.controlPoints.count - 1
                ),
                migratedEndReference: .splineControlPoint(
                    entity: newEntityID,
                    index: split.new.controlPoints.count - 1
                )
            )
        case .arc(let arc):
            let split = try splitArc(
                arc,
                fraction: fraction,
                owner: owner
            )
            try validateArc(split.retained, owner: owner)
            try validateArc(split.new, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .arc(split.retained),
                newEntity: .arc(split.new),
                insertedRetainedReference: .arcEnd(entityID),
                insertedNewReference: .arcStart(newEntityID),
                originalEndReference: .arcEnd(entityID),
                migratedEndReference: .arcEnd(newEntityID)
            )
        case .point,
             .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line, arc, or spline curve target."
            )
        }
    }

    private func splitArc(
        _ arc: SketchArc,
        fraction: Double,
        owner: String
    ) throws -> (retained: SketchArc, new: SketchArc) {
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let splitAngle = startAngle + span * fraction
        let splitExpression = CADExpression.angle(splitAngle, .radian)
        return (
            retained: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: splitExpression
            ),
            new: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: splitExpression,
                endAngle: arc.endAngle
            )
        )
    }

    private func splitPoint(
        on line: SketchLine,
        fraction: Double,
        owner: String
    ) throws -> SketchPoint {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        guard hypot(deltaX, deltaY) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return sketchPoint(
            x: startX + deltaX * fraction,
            y: startY + deltaY * fraction
        )
    }

    private func splitSpline(
        _ spline: SketchSpline,
        fraction: Double,
        owner: String
    ) throws -> (retained: SketchSpline, new: SketchSpline) {
        let controlPoints = spline.controlPoints
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let scaledParameter = fraction * Double(segmentCount)
        var segmentIndex = Int(floor(scaledParameter))
        let localFraction = scaledParameter - Double(segmentIndex)
        let tolerance = 1.0e-9

        if localFraction <= tolerance {
            guard segmentIndex > 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) fraction must not resolve to the spline start."
                )
            }
            return splitSplineAtExistingKnot(
                spline,
                knotIndex: segmentIndex * 3,
                owner: owner
            )
        }
        if localFraction >= 1.0 - tolerance {
            segmentIndex += 1
            guard segmentIndex < segmentCount else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) fraction must not resolve to the spline end."
                )
            }
            return splitSplineAtExistingKnot(
                spline,
                knotIndex: segmentIndex * 3,
                owner: owner
            )
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let split = splitCubicBezier(
            p0,
            p1,
            p2,
            p3,
            fraction: .scalar(localFraction)
        )
        var retained = Array(controlPoints[0 ... segmentStart])
        retained.append(contentsOf: [split.left.1, split.left.2, split.left.3])
        var next = [split.right.0, split.right.1, split.right.2, split.right.3]
        if segmentStart + 4 < controlPoints.count {
            next.append(contentsOf: controlPoints[(segmentStart + 4)...])
        }
        guard retained.count >= 4,
              next.count >= 4 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced an invalid spline split."
            )
        }
        return (
            retained: SketchSpline(controlPoints: retained),
            new: SketchSpline(controlPoints: next)
        )
    }

    private func splitSplineAtExistingKnot(
        _ spline: SketchSpline,
        knotIndex: Int,
        owner: String
    ) -> (retained: SketchSpline, new: SketchSpline) {
        let controlPoints = spline.controlPoints
        precondition(knotIndex > 0 && knotIndex < controlPoints.count - 1)
        let retained = Array(controlPoints[0 ... knotIndex])
        let next = Array(controlPoints[knotIndex...])
        return (
            retained: SketchSpline(controlPoints: retained),
            new: SketchSpline(controlPoints: next)
        )
    }

    private func splitCubicBezier(
        _ p0: SketchPoint,
        _ p1: SketchPoint,
        _ p2: SketchPoint,
        _ p3: SketchPoint,
        fraction: CADExpression
    ) -> (
        left: (SketchPoint, SketchPoint, SketchPoint, SketchPoint),
        right: (SketchPoint, SketchPoint, SketchPoint, SketchPoint)
    ) {
        let q0 = interpolatedSketchPoint(p0, p1, fraction: fraction)
        let q1 = interpolatedSketchPoint(p1, p2, fraction: fraction)
        let q2 = interpolatedSketchPoint(p2, p3, fraction: fraction)
        let r0 = interpolatedSketchPoint(q0, q1, fraction: fraction)
        let r1 = interpolatedSketchPoint(q1, q2, fraction: fraction)
        let s = interpolatedSketchPoint(r0, r1, fraction: fraction)
        return (
            left: (p0, q0, r0, s),
            right: (s, r1, q2, p3)
        )
    }

    private func interpolatedSketchPoint(
        _ first: SketchPoint,
        _ second: SketchPoint,
        fraction: CADExpression
    ) -> SketchPoint {
        SketchPoint(
            x: .add(first.x, .multiply(.subtract(second.x, first.x), fraction)),
            y: .add(first.y, .multiply(.subtract(second.y, first.y), fraction))
        )
    }

    private func constraintsAfterSketchCurveSplit(
        _ constraints: [SketchConstraint],
        split: SketchCurveSegmentSplitResult
    ) -> [SketchConstraint] {
        var updated: [SketchConstraint] = []
        for constraint in constraints {
            switch constraint {
            case .coincident(let first, let second):
                updated.append(.coincident(
                    rewriteSketchReferenceAfterCurveSplit(first, split: split),
                    rewriteSketchReferenceAfterCurveSplit(second, split: split)
                ))
            case .fixed(let reference):
                updated.append(.fixed(rewriteSketchReferenceAfterCurveSplit(reference, split: split)))
            case .horizontal(let entityID):
                updated.append(constraint)
                if entityID == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.horizontal(split.newEntityID))
                }
            case .vertical(let entityID):
                updated.append(constraint)
                if entityID == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.vertical(split.newEntityID))
                }
            case .parallel(let first, let second):
                updated.append(constraint)
                if first == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.parallel(split.newEntityID, second))
                } else if second == split.originalEntityID,
                          case .line = split.retainedEntity {
                    updated.append(.parallel(first, split.newEntityID))
                }
            case .perpendicular(let first, let second):
                updated.append(constraint)
                if first == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.perpendicular(split.newEntityID, second))
                } else if second == split.originalEntityID,
                          case .line = split.retainedEntity {
                    updated.append(.perpendicular(first, split.newEntityID))
                }
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                if splineID == split.originalEntityID,
                   endpoint == .end {
                    updated.append(.splineEndpointTangent(
                        spline: split.newEntityID,
                        endpoint: .end,
                        line: lineID
                    ))
                } else {
                    updated.append(constraint)
                }
            case .tangentSplineEndpoints(let first, let second):
                updated.append(.tangentSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveSplit(first, split: split),
                    second: rewriteSplineEndpointReferenceAfterCurveSplit(second, split: split)
                ))
            case .smoothSplineEndpoints(let first, let second):
                updated.append(.smoothSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveSplit(first, split: split),
                    second: rewriteSplineEndpointReferenceAfterCurveSplit(second, split: split)
                ))
            case .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint:
                updated.append(constraint)
            }
        }
        updated.append(.coincident(split.insertedRetainedReference, split.insertedNewReference))
        return updated
    }

    private func dimensionsAfterSketchCurveSplit(
        _ dimensions: [SketchDimension],
        split: SketchCurveSegmentSplitResult
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteSketchReferenceAfterCurveSplit(from, split: split),
                    to: rewriteSketchReferenceAfterCurveSplit(to, split: split),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteSketchReferenceAfterCurveSplit(from, split: split),
                    to: rewriteSketchReferenceAfterCurveSplit(to, split: split),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private func bridgeCurveSourcesAfterSketchCurveSplit(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        split: SketchCurveSegmentSplitResult
    ) throws -> [BridgeCurveSourceID: BridgeCurveSource] {
        try sources.mapValues { source in
            BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: try rewriteBridgeEndpointAfterCurveSplit(source.firstEndpoint, split: split),
                secondEndpoint: try rewriteBridgeEndpointAfterCurveSplit(source.secondEndpoint, split: split),
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
    }

    private func rewriteBridgeEndpointAfterCurveSplit(
        _ endpoint: BridgeCurveEndpoint,
        split: SketchCurveSegmentSplitResult
    ) throws -> BridgeCurveEndpoint {
        guard let parameter = endpoint.parameter,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: split.originalEntityID) else {
            return BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveSplit(endpoint.reference, split: split),
                parameter: endpoint.parameter,
                reversesSense: endpoint.reversesSense,
                tension: endpoint.tension
            )
        }

        let resolvedParameter = try resolvedScalarValue(
            parameter,
            owner: "Bridge curve endpoint parameter"
        )
        let splitExpression = CADExpression.scalar(split.fraction)
        if resolvedParameter <= split.fraction {
            return BridgeCurveEndpoint(
                reference: endpoint.reference,
                parameter: .divide(parameter, splitExpression),
                reversesSense: endpoint.reversesSense,
                tension: endpoint.tension
            )
        }
        return BridgeCurveEndpoint(
            reference: rewriteBridgeParametricReferenceToNewSplitEntity(
                endpoint.reference,
                split: split
            ),
            parameter: .divide(
                .subtract(parameter, splitExpression),
                .subtract(.scalar(1.0), splitExpression)
            ),
            reversesSense: endpoint.reversesSense,
            tension: endpoint.tension
        )
    }

    private func rewriteBridgeParametricReferenceToNewSplitEntity(
        _ reference: SketchReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchReference {
        switch reference {
        case .entity(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .lineStart(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .lineEnd(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .arcStart(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .arcEnd(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .splineControlPoint(let entityID, _) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        default:
            return reference
        }
    }

    private func rewriteSketchReferenceAfterCurveSplit(
        _ reference: SketchReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchReference {
        reference == split.originalEndReference ? split.migratedEndReference : reference
    }

    private func rewriteSplineEndpointReferenceAfterCurveSplit(
        _ reference: SketchSplineEndpointReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchSplineEndpointReference {
        guard reference.splineID == split.originalEntityID,
              reference.endpoint == .end else {
            return reference
        }
        return SketchSplineEndpointReference(splineID: split.newEntityID, endpoint: .end)
    }

    private func bridgeCurveSourcesAfterSketchCurveReverse(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [BridgeCurveSourceID: BridgeCurveSource] {
        sources.mapValues { source in
            let firstEndpoint = BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveReverse(
                    source.firstEndpoint.reference,
                    entityID: entityID,
                    splineControlPointCount: splineControlPointCount
                ),
                parameter: rewriteBridgeEndpointParameterAfterCurveReverse(
                    source.firstEndpoint,
                    entityID: entityID
                ),
                reversesSense: rewriteBridgeEndpointSenseAfterCurveReverse(
                    source.firstEndpoint,
                    entityID: entityID
                ),
                tension: source.firstEndpoint.tension
            )
            let secondEndpoint = BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveReverse(
                    source.secondEndpoint.reference,
                    entityID: entityID,
                    splineControlPointCount: splineControlPointCount
                ),
                parameter: rewriteBridgeEndpointParameterAfterCurveReverse(
                    source.secondEndpoint,
                    entityID: entityID
                ),
                reversesSense: rewriteBridgeEndpointSenseAfterCurveReverse(
                    source.secondEndpoint,
                    entityID: entityID
                ),
                tension: source.secondEndpoint.tension
            )
            if source.featureID == featureID && source.entityID == entityID {
                return BridgeCurveSource(
                    id: source.id,
                    featureID: source.featureID,
                    entityID: source.entityID,
                    firstEndpoint: secondEndpoint,
                    secondEndpoint: firstEndpoint,
                    continuity: source.continuity,
                    trimsSourceCurves: source.trimsSourceCurves
                )
            }
            return BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint,
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
    }

    private func rewriteSketchReferenceAfterCurveReverse(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .lineEnd(entityID)
        case .lineEnd(let id) where id == entityID:
            return .lineStart(entityID)
        case .splineControlPoint(let id, let index) where id == entityID:
            guard let count = splineControlPointCount else {
                return reference
            }
            return .splineControlPoint(
                entity: entityID,
                index: reversedSplineControlPointIndex(index, controlPointCount: count)
            )
        default:
            return reference
        }
    }

    private func rewriteBridgeEndpointParameterAfterCurveReverse(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> CADExpression? {
        guard let parameter = endpoint.parameter,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID) else {
            return endpoint.parameter
        }
        return .subtract(.scalar(1.0), parameter)
    }

    private func rewriteBridgeEndpointSenseAfterCurveReverse(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> Bool {
        guard endpoint.parameter != nil,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID) else {
            return endpoint.reversesSense
        }
        return !endpoint.reversesSense
    }

    private func rewriteSplineEndpointReferenceAfterCurveReverse(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID
    ) -> SketchSplineEndpointReference {
        guard reference.splineID == entityID else {
            return reference
        }
        return SketchSplineEndpointReference(
            splineID: reference.splineID,
            endpoint: reversedSplineEndpoint(reference.endpoint)
        )
    }

    private func reversedSplineEndpoint(_ endpoint: SketchSplineEndpoint) -> SketchSplineEndpoint {
        switch endpoint {
        case .start:
            return .end
        case .end:
            return .start
        }
    }

    private func reversedSplineControlPointIndex(
        _ index: Int,
        controlPointCount: Int
    ) -> Int {
        controlPointCount - 1 - index
    }

    private func convertedLineSplineEndpointForTangency(
        source: SketchSplineEndpointReference,
        lineID: SketchEntityID,
        constraints: [SketchConstraint],
        originalSketch: Sketch,
        owner: String
    ) throws -> SketchSplineEndpoint {
        let sourceReference = try splineEndpointPointReference(source, in: originalSketch, owner: owner)
        let connectedReferences = coincidentPointReferences(
            connectedTo: sourceReference,
            constraints: constraints
        )
        if connectedReferences.contains(.lineStart(lineID)) {
            return .start
        }
        if connectedReferences.contains(.lineEnd(lineID)) {
            return .end
        }

        guard let sourcePoint = try resolvedPoint(sourceReference, in: originalSketch, owner: owner),
              let startPoint = try resolvedPoint(.lineStart(lineID), in: originalSketch, owner: owner),
              let endPoint = try resolvedPoint(.lineEnd(lineID), in: originalSketch, owner: owner) else {
            return .start
        }
        let startDistance = squaredDistance(sourcePoint, startPoint)
        let endDistance = squaredDistance(sourcePoint, endPoint)
        return startDistance <= endDistance ? .start : .end
    }

    private func splineEndpointPointReference(
        _ endpoint: SketchSplineEndpointReference,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchReference {
        guard let entity = sketch.entities[endpoint.splineID],
              case let .spline(spline) = entity,
              spline.controlPoints.count >= 4 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a spline endpoint reference."
            )
        }
        switch endpoint.endpoint {
        case .start:
            return .splineControlPoint(entity: endpoint.splineID, index: 0)
        case .end:
            return .splineControlPoint(entity: endpoint.splineID, index: spline.controlPoints.count - 1)
        }
    }

    private func coincidentPointReferences(
        connectedTo reference: SketchReference,
        constraints: [SketchConstraint]
    ) -> Set<SketchReference> {
        var connectedReferences: Set<SketchReference> = [reference]
        var changed = true
        while changed {
            changed = false
            for constraint in constraints {
                guard case let .coincident(first, second) = constraint else {
                    continue
                }
                if connectedReferences.contains(first), connectedReferences.insert(second).inserted {
                    changed = true
                }
                if connectedReferences.contains(second), connectedReferences.insert(first).inserted {
                    changed = true
                }
            }
        }
        return connectedReferences
    }

    private func squaredDistance(
        _ first: (x: Double, y: Double),
        _ second: (x: Double, y: Double)
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    private func isLineEndpointReference(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case .lineStart(let id), .lineEnd(let id):
            return id == entityID
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            return false
        }
    }

    private func lineSplineConversionError(
        _ owner: String,
        reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "\(owner) cannot preserve \(reason) as spline point references."
        )
    }

    private func sketchReference(
        _ reference: SketchReference,
        references entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case .entity(let id),
             .lineStart(let id),
             .lineEnd(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id),
             .splineControlPoint(let id, _):
            return id == entityID
        }
    }

    private func dimensionsAfterSettingEntityDimension(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        entity: SketchEntity,
        kind: SketchEntityDimensionKind,
        value: CADExpression
    ) -> [SketchDimension] {
        var next = dimensions.filter { dimension in
            switch kind {
            case .length:
                return isLineLengthDimension(dimension, entityID: entityID) == false
            case .radius, .diameter:
                return isCircularSizeDimension(dimension, entityID: entityID) == false
            case .angle:
                switch entity {
                case .line:
                    return isLineAngleDimension(dimension, entityID: entityID) == false
                case .arc:
                    return isArcAngleDimension(dimension, entityID: entityID) == false
                case .point, .circle, .spline:
                    return true
                }
            }
        }
        switch kind {
        case .length:
            next.append(.distance(from: .lineStart(entityID), to: .lineEnd(entityID), value: value))
        case .radius:
            next.append(.radius(entity: entityID, value: value))
        case .diameter:
            next.append(.diameter(entity: entityID, value: value))
        case .angle:
            switch entity {
            case .line:
                next.append(.angle(from: .lineStart(entityID), to: .lineEnd(entityID), value: value))
            case .arc:
                next.append(.angle(from: .arcStart(entityID), to: .arcEnd(entityID), value: value))
            case .point, .circle, .spline:
                return next
            }
        }
        return next
    }

    private func isLineLengthDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        guard case let .distance(first, second, _) = dimension else {
            return false
        }
        return referencesLineEndpoints(first, second, entityID: entityID)
    }

    private func referencesLineEndpoints(
        _ first: SketchReference,
        _ second: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch (first, second) {
        case (.lineStart(let firstID), .lineEnd(let secondID)),
             (.lineEnd(let firstID), .lineStart(let secondID)):
            return firstID == entityID && secondID == entityID
        default:
            return false
        }
    }

    private func isLineAngleDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        guard case let .angle(first, second, _) = dimension else {
            return false
        }
        return referencesLineEndpoints(first, second, entityID: entityID)
    }

    private func isCircularSizeDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        switch dimension {
        case .radius(let id, _), .diameter(let id, _):
            return id == entityID
        case .distance, .angle:
            return false
        }
    }

    private func isArcAngleDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        guard case let .angle(first, second, _) = dimension else {
            return false
        }
        return referencesArcEndpoints(first, second, entityID: entityID)
    }

    private func referencesArcEndpoints(
        _ first: SketchReference,
        _ second: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch (first, second) {
        case (.arcStart(let firstID), .arcEnd(let secondID)),
             (.arcEnd(let firstID), .arcStart(let secondID)):
            return firstID == entityID && secondID == entityID
        default:
            return false
        }
    }

    private func rewriteLineEndpointReference(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .arcStart(entityID)
        case .lineEnd(let id) where id == entityID:
            return .arcEnd(entityID)
        default:
            return reference
        }
    }

    private func rewriteLineEndpointToSplineReference(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .splineControlPoint(entity: entityID, index: 0)
        case .lineEnd(let id) where id == entityID:
            return .splineControlPoint(entity: entityID, index: 3)
        default:
            return reference
        }
    }

    private func validateArc(
        _ arc: SketchArc,
        owner: String
    ) throws {
        _ = try resolvedLengthValue(arc.center.x, owner: "\(owner) center x")
        _ = try resolvedLengthValue(arc.center.y, owner: "\(owner) center y")
        _ = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let resolvedStartAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let resolvedEndAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        _ = try normalizedPartialArcSpan(
            startAngle: resolvedStartAngle,
            endAngle: resolvedEndAngle
        )
    }

    private func validateSpline(
        _ spline: SketchSpline,
        owner: String
    ) throws {
        let count = spline.controlPoints.count
        guard count >= 4, (count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) control point count must be 3n + 1 and at least 4."
            )
        }
        let resolvedPoints = try spline.controlPoints.enumerated().map { index, point in
            (
                x: try resolvedLengthValue(point.x, owner: "\(owner) control point \(index) x"),
                y: try resolvedLengthValue(point.y, owner: "\(owner) control point \(index) y")
            )
        }
        for segmentIndex in stride(from: 0, to: resolvedPoints.count - 1, by: 3) {
            let start = resolvedPoints[segmentIndex]
            let end = resolvedPoints[segmentIndex + 3]
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            guard sqrt(deltaX * deltaX + deltaY * deltaY) > ModelingTolerance.standard.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cubic segment \(segmentIndex / 3) must not collapse to a point."
                )
            }
        }
    }

    private mutating func commitSketchEntityEdit(
        featureID: FeatureID,
        feature: inout FeatureNode,
        sketch: Sketch,
        objectRegistry: ObjectTypeRegistry,
        errorOwner: String
    ) throws {
        feature.operation = .sketch(sketch)
        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(errorOwner) produced invalid sketch geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeSketchObjectProperties(
            featureID: featureID,
            sketch: sketch,
            objectRegistry: objectRegistry
        )
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private mutating func synchronizeSketchObjectProperties(
        featureID: FeatureID,
        sketch: Sketch,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard sketch.entities.count == 1,
              let entity = sketch.entities.values.first else {
            return
        }
        switch entity {
        case .line(let line):
            let metrics = try resolvedLineMetrics(line, owner: "Sketch line")
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .line else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "length"),
                    to: metrics.length,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "angle"),
                    to: metrics.angleDegrees,
                    object: &object,
                    definition: definition
                )
            }
        case .circle(let circle):
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "Sketch circle radius")
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .circle else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "radius"),
                    to: radius,
                    object: &object,
                    definition: definition
                )
            }
        case .arc(let arc):
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "Sketch arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "Sketch arc start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "Sketch arc end angle")
            let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .arc else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "radius"),
                    to: radius,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "start.angle"),
                    to: startAngle * 180.0 / .pi,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "end.angle"),
                    to: (startAngle + span) * 180.0 / .pi,
                    object: &object,
                    definition: definition
                )
            }
        case .spline(let spline):
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .spline else {
                    return
                }
                Self.setIntegerProperty(
                    ObjectPropertyID(rawValue: "control.point.count"),
                    to: spline.controlPoints.count,
                    object: &object,
                    definition: definition
                )
            }
        case .point:
            return
        }
    }

    private mutating func updateSketchObjectProperties(
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry,
        update: (inout ObjectDescriptor, ObjectTypeDefinition) -> Void
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch,
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

    private mutating func setSketchObjectType(
        featureID: FeatureID,
        typeID: ObjectTypeID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch else {
            return
        }

        let definition = try objectRegistry.requireDefinition(for: typeID)
        var nextProperties = objectRegistry.defaultProperties(for: typeID)
        if let strokeWidth = object.properties[ObjectPropertyID(rawValue: "stroke.width")] {
            nextProperties[ObjectPropertyID(rawValue: "stroke.width")] = strokeWidth
        }
        nextProperties = definition.resolvedProperties(nextProperties)
        try nextProperties.validate(
            against: definition,
            materialLibrary: productMetadata.materialLibrary
        )
        object.typeID = typeID
        object.geometryRole = definition.geometryRole
        object.properties = nextProperties
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    private mutating func markSketchObjectAsSourceEdited(featureID: FeatureID) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch else {
            return
        }
        object.typeID = nil
        object.properties = ObjectPropertySet()
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
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

    private mutating func markBodyObjectAsSourceEditedSolid(
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

    private static func setLengthProperty(
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

    private static func setAngleProperty(
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

    private static func setIntegerProperty(
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

    private static func normalizedAngleDegrees(_ degrees: Double) -> Double {
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
            outputs: [
                FeatureOutput(role: .profile),
                FeatureOutput(role: .curve),
            ]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSketch = false
        defer {
            if didCommitSketch == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
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
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitSketch = true
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

    private func resolvedAngleValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite angle."
            )
        }
        return quantity.value
    }

    private func resolvedScalarValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .scalar else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a scalar."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite scalar."
            )
        }
        return quantity.value
    }

    private func resolvedPositiveScalarValue(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let value = try resolvedScalarValue(expression, owner: owner)
        guard value > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must be greater than zero."
            )
        }
        return value
    }

    private func validateSweepOptionQuantities(_ options: SweepOptions) throws {
        if let unsupportedCase = SweepEvaluationCapabilities().staticUnsupportedCase(for: options) {
            throw EditorError(
                code: .commandInvalid,
                message: unsupportedCase.message
            )
        }
        _ = try resolvedAngleValue(options.twistAngle, owner: "Sweep twist angle")
        let endScale = try resolvedScalarValue(options.endScale, owner: "Sweep end scale")
        guard endScale > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep end scale must be greater than zero."
            )
        }
        let distanceFraction = try resolvedScalarValue(
            options.distanceFraction,
            owner: "Sweep distance fraction"
        )
        guard distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep distance fraction must be greater than 0 and less than or equal to 1."
            )
        }
    }

    private func normalizedPartialArcSpan(
        startAngle: Double,
        endAngle: Double
    ) throws -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= ModelingTolerance.standard.angle {
            span += fullCircle
        }
        while span > fullCircle + ModelingTolerance.standard.angle {
            span -= fullCircle
        }
        guard span > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch angle span must be greater than zero."
            )
        }
        guard span < fullCircle - ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch must be partial; use a circle sketch for full circles."
            )
        }
        return span
    }

    private func validatePolygonSides(_ sides: Int) throws {
        guard sides >= 3, sides <= 256 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Polygon sketch sides must be between 3 and 256."
            )
        }
    }

    private func polygonSketch(
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        sides: Int,
        rotationAngle: CADExpression
    ) -> Sketch {
        let entityIDs = (0..<sides).map { _ in SketchEntityID() }
        let vertices = (0..<sides).map { index in
            polygonVertex(
                center: center,
                radius: radius,
                rotationAngle: rotationAngle,
                vertexIndex: index,
                sides: sides
            )
        }
        var entities: [SketchEntityID: SketchEntity] = [:]
        var constraints: [SketchConstraint] = []

        for index in 0..<sides {
            let nextIndex = (index + 1) % sides
            let entityID = entityIDs[index]
            entities[entityID] = .line(
                SketchLine(
                    start: vertices[index],
                    end: vertices[nextIndex]
                )
            )
            constraints.append(
                .coincident(
                    .lineEnd(entityID),
                    .lineStart(entityIDs[nextIndex])
                )
            )
        }

        if let firstEntityID = entityIDs.first {
            for entityID in entityIDs.dropFirst() {
                constraints.append(.equalLength(firstEntityID, entityID))
            }
        }

        return Sketch(
            plane: plane,
            entities: entities,
            constraints: constraints
        )
    }

    private func polygonCircumradiusExpression(
        _ radius: CADExpression,
        sides: Int,
        sizingMode: PolygonSizingMode
    ) -> CADExpression {
        switch sizingMode {
        case .circumradius:
            return radius
        case .inradius:
            return .divide(
                radius,
                .cos(.angle(Double.pi / Double(sides), .radian))
            )
        }
    }

    private func polygonVertex(
        center: SketchPoint,
        radius: CADExpression,
        rotationAngle: CADExpression,
        vertexIndex: Int,
        sides: Int
    ) -> SketchPoint {
        let stepAngle = CADExpression.angle(
            Double(vertexIndex) * 2.0 * Double.pi / Double(sides),
            .radian
        )
        let angle = CADExpression.add(rotationAngle, stepAngle)
        return SketchPoint(
            x: .add(center.x, .multiply(radius, .cos(angle))),
            y: .add(center.y, .multiply(radius, .sin(angle)))
        )
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

    private func sketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x, .meter),
            y: .length(y, .meter)
        )
    }

    private func editableBodyFace(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyFace {
        guard case .face(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset requires a face selection target."
            )
        }
        if componentID.generatedTopologyPersistentName != nil {
            let bodyFace = try GeneratedTopologySelectionResolver().bodyFace(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: "Face offset"
            )
            return editableBodyFace(for: bodyFace)
        }
        switch componentID {
        case .bodyFaceFront:
            return .front
        case .bodyFaceBack:
            return .back
        case .bodyFaceTop:
            return .top
        case .bodyFaceBottom:
            return .bottom
        case .bodyFaceLeft:
            return .left
        case .bodyFaceRight:
            return .right
        case .bodyFaceSide:
            return .side
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset target is not an editable body face."
            )
        }
    }

    private func editableBodyFace(for bodyFace: BodyFace) -> EditableBodyFace {
        switch bodyFace {
        case .front:
            return .front
        case .back:
            return .back
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .left:
            return .left
        case .right:
            return .right
        case .side:
            return .side
        }
    }

    private func validateEditableBodyCandidate(
        _ updatedCADDocument: CADDocument,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        do {
            try updatedCADDocument.validate()
            var candidate = self
            candidate.cadDocument = updatedCADDocument
            _ = try CADPipeline
                .modelingDefault(for: candidate, objectRegistry: objectRegistry)
                .evaluate(updatedCADDocument)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) produced invalid geometry: \(error)."
            )
        }
    }

    private func rectangleProfileLoopVertexIndices(
        for targets: [SelectionTarget],
        profileLoop: EditableExtrudeProfileLoop,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Set<Int> {
        var targetIndices = Set<Int>()
        for target in targets {
            let edge = try editableBodyEdge(
                for: target,
                operationName: operationName,
                objectRegistry: objectRegistry
            )
            let vertex = rectangleProfilePoint(for: edge, bounds: bounds)
            guard let index = profileLoop.closestVertexIndex(to: vertex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) rectangle edge target does not match an editable profile loop vertex."
                )
            }
            targetIndices.insert(index)
        }
        return targetIndices
    }

    private func rectangleProfilePoint(
        for edge: EditableBodyEdge,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)
    ) -> EditableExtrudeProfileLoop.Point {
        switch edge {
        case .leftBottom:
            EditableExtrudeProfileLoop.Point(x: bounds.minX, y: bounds.minY)
        case .rightBottom:
            EditableExtrudeProfileLoop.Point(x: bounds.maxX, y: bounds.minY)
        case .rightTop:
            EditableExtrudeProfileLoop.Point(x: bounds.maxX, y: bounds.maxY)
        case .leftTop:
            EditableExtrudeProfileLoop.Point(x: bounds.minX, y: bounds.maxY)
        }
    }

    private func generatedProfileLoopVertexIndices(
        for targets: [SelectionTarget],
        profileLoop: EditableExtrudeProfileLoop,
        sketchPlane: SketchPlane,
        expectedKind: TopologySummaryResult.Entry.Kind,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Set<Int> {
        var targetIndices = Set<Int>()
        for target in targets {
            let index = try profileLoopVertexIndex(
                for: target,
                profileLoop: profileLoop,
                sketchPlane: sketchPlane,
                expectedKind: expectedKind,
                operationName: operationName,
                objectRegistry: objectRegistry
            )
            targetIndices.insert(index)
        }
        return targetIndices
    }

    private func profileLoopVertexIndex(
        for target: SelectionTarget,
        profileLoop: EditableExtrudeProfileLoop,
        sketchPlane: SketchPlane,
        expectedKind: TopologySummaryResult.Entry.Kind,
        operationName: String,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Int {
        let componentID: SelectionComponentID
        switch (expectedKind, target.component) {
        case (.edge, .edge(let edgeComponentID)):
            componentID = edgeComponentID
        case (.vertex, .vertex(let vertexComponentID)):
            componentID = vertexComponentID
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated topology \(expectedKind.rawValue) targets for non-rectangle profile loops."
            )
        }
        guard let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated topology targets for non-rectangle profile loops."
            )
        }
        let topology = try TopologySummaryService().summarize(
            document: self,
            objectRegistry: objectRegistry
        )
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology target was not found in the current evaluation."
            )
        }
        guard entry.sceneNodeID == target.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference the selected body."
            )
        }
        guard entry.kind == expectedKind else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference a \(expectedKind.rawValue) on the selected body."
            )
        }
        let tolerance = 1.0e-8
        let point: EditableExtrudeProfileLoop.Point
        switch entry.kind {
        case .edge:
            guard let start = entry.start,
                  let end = entry.end else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) generated topology target must reference an edge on the selected body."
                )
            }
            let startCoordinate = try sketchCoordinate(from: start, on: sketchPlane)
            let endCoordinate = try sketchCoordinate(from: end, on: sketchPlane)
            guard nearlyEqual(startCoordinate.x, endCoordinate.x, tolerance: tolerance),
                  nearlyEqual(startCoordinate.y, endCoordinate.y, tolerance: tolerance),
                  !nearlyEqual(startCoordinate.depth, endCoordinate.depth, tolerance: tolerance) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) generated topology target is not a vertical profile edge."
                )
            }
            point = EditableExtrudeProfileLoop.Point(
                x: (startCoordinate.x + endCoordinate.x) / 2.0,
                y: (startCoordinate.y + endCoordinate.y) / 2.0
            )
        case .vertex:
            guard let start = entry.start else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) generated topology target must reference a vertex on the selected body."
                )
            }
            let coordinate = try sketchCoordinate(from: start, on: sketchPlane)
            point = EditableExtrudeProfileLoop.Point(
                x: coordinate.x,
                y: coordinate.y
            )
        case .body, .face:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated topology target must reference an edge or vertex on the selected body."
            )
        }
        guard let index = profileLoop.closestVertexIndex(to: point, tolerance: tolerance) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology edge does not match an editable profile loop vertex."
            )
        }
        return index
    }

    private func sketchCoordinate(
        from point: TopologySummaryResult.Entry.Point,
        on plane: SketchPlane
    ) throws -> (x: Double, y: Double, depth: Double) {
        switch plane {
        case .xy:
            return (x: point.x, y: point.y, depth: point.z)
        case .yz:
            return (x: point.y, y: point.z, depth: point.x)
        case .zx:
            return (x: point.z, y: point.x, depth: point.y)
        case .plane(let plane):
            let normal = try plane.normal.normalized(tolerance: 1.0e-12)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: 1.0e-12)
            let v = normal.cross(u)
            let delta = Point3D(x: point.x, y: point.y, z: point.z) - plane.origin
            return (
                x: delta.dot(u),
                y: delta.dot(v),
                depth: delta.dot(normal)
            )
        }
    }

    private func editableBodyEdge(
        for target: SelectionTarget,
        operationName: String = "Edge chamfer",
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyEdge {
        guard case .edge(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires edge selection targets."
            )
        }
        if componentID.generatedTopologyPersistentName != nil {
            let cornerEdge = try GeneratedTopologySelectionResolver().cornerEdge(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: operationName
            )
            return editableBodyEdge(for: cornerEdge)
        }
        switch componentID {
        case .bodyEdgeLeftBottom:
            return .leftBottom
        case .bodyEdgeRightBottom:
            return .rightBottom
        case .bodyEdgeRightTop:
            return .rightTop
        case .bodyEdgeLeftTop:
            return .leftTop
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target is not an editable body edge."
            )
        }
    }

    private func editableBodyEdge(for cornerEdge: BodyCornerEdge) -> EditableBodyEdge {
        switch cornerEdge {
        case .leftBottom:
            return .leftBottom
        case .rightBottom:
            return .rightBottom
        case .rightTop:
            return .rightTop
        case .leftTop:
            return .leftTop
        }
    }

    private func editableBodyVertex(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyVertex {
        guard case .vertex(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Vertex move requires a vertex selection target."
            )
        }
        if componentID.generatedTopologyPersistentName != nil {
            let cornerVertex = try GeneratedTopologySelectionResolver().cornerVertex(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: "Vertex move"
            )
            return editableBodyVertex(for: cornerVertex)
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Vertex move target is not an editable generated body vertex."
        )
    }

    private func editableBodyVertex(for cornerVertex: BodyCornerVertex) -> EditableBodyVertex {
        switch cornerVertex {
        case .frontBottomLeft, .backBottomLeft:
            return .bottomLeft
        case .frontBottomRight, .backBottomRight:
            return .bottomRight
        case .frontTopRight, .backTopRight:
            return .topRight
        case .frontTopLeft, .backTopLeft:
            return .topLeft
        }
    }

    private func offsetExtrudeDepth(
        extrude: inout ExtrudeFeature,
        face: EditableBodyFace,
        offsetMeters: Double
    ) throws -> Double {
        guard face == .front || face == .back else {
            return try resolvedPositiveLengthValue(extrude.distance, owner: "Extrude distance")
        }
        guard case .normal = extrude.direction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Front and back face offset currently requires a normal extrude."
            )
        }
        let depthMeters = try resolvedLengthValue(extrude.distance, owner: "Extrude distance")
        guard depthMeters > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Front and back face offset currently requires a positive extrude distance."
            )
        }
        let nextDepth = depthMeters + offsetMeters
        guard nextDepth > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset would collapse the extrude body."
            )
        }
        return nextDepth
    }

    private mutating func offsetCylinderFace(
        face: EditableBodyFace,
        offsetMeters: Double,
        circleEntry: (id: SketchEntityID, circle: SketchCircle),
        sketch: inout Sketch,
        profileFeature: inout FeatureNode,
        feature: inout FeatureNode,
        extrude: inout ExtrudeFeature,
        featureID: FeatureID,
        sceneNodeID: SceneNodeID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        var radiusMeters = try resolvedPositiveLengthValue(
            circleEntry.circle.radius,
            owner: "Cylinder radius"
        )
        var translationYDelta = 0.0
        var updatesProfile = false
        switch face {
        case .side:
            radiusMeters += offsetMeters
            guard radiusMeters > 1.0e-9 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Face offset would collapse the cylinder radius."
                )
            }
            sketch.entities[circleEntry.id] = .circle(
                SketchCircle(
                    center: circleEntry.circle.center,
                    radius: .length(radiusMeters, .meter)
                )
            )
            profileFeature.operation = .sketch(sketch)
            updatesProfile = true
        case .front, .back:
            let nextDepth = try offsetExtrudeDepth(
                extrude: &extrude,
                face: face,
                offsetMeters: offsetMeters
            )
            if face == .front {
                translationYDelta = -offsetMeters
            }
            extrude.distance = .length(nextDepth, .meter)
            feature.operation = .extrude(extrude)
        case .top, .bottom, .left, .right:
            throw EditorError(
                code: .commandInvalid,
                message: "Cylinder face offset supports front, back, and side faces."
            )
        }

        var updatedCADDocument = cadDocument
        do {
            if updatesProfile {
                try updatedCADDocument.replaceFeatures([profileFeature, feature])
            } else {
                try updatedCADDocument.replaceFeature(feature)
            }
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cylinder face offset produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        if abs(translationYDelta) > 0.0 {
            try translateSceneNode(sceneNodeID, y: translationYDelta)
        }
        let sizeY = abs(try resolvedLengthValue(extrude.distance, owner: "Extrude distance"))
        try synchronizeCylinderObjectProperties(
            featureID: featureID,
            radius: radiusMeters,
            sizeY: sizeY,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    private mutating func translateSceneNode(
        _ id: SceneNodeID,
        y delta: Double
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Face offset lost its scene node."
            )
        }
        var values = node.localTransform.matrix.values
        if values.count != 16 {
            values = Matrix4x4.identity.values
        }
        values[13] += delta
        node.localTransform = Transform3D(matrix: try Matrix4x4(values: values))
        productMetadata.sceneNodes[id] = node
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

    private func rectangleSideDimensionAxis(
        in sketch: Sketch,
        entityID: SketchEntityID
    ) throws -> RectangleSideDimensionAxis? {
        guard let lineIDs = try rectangleLineIDs(in: sketch) else {
            return nil
        }
        if entityID == lineIDs.bottom || entityID == lineIDs.top {
            return .width
        }
        if entityID == lineIDs.left || entityID == lineIDs.right {
            return .height
        }
        return nil
    }

    private func updateRectangleSketchForSideDimension(
        _ sketch: inout Sketch,
        axis: RectangleSideDimensionAxis,
        length: CADExpression,
        resolvedLength: Double
    ) throws {
        guard let bounds = try resolvedSketchBounds2D(sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch line dimension update requires a finite rectangle profile."
            )
        }
        guard resolvedLength > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line dimension would collapse the rectangle profile."
            )
        }
        let fixedSnapshot = try fixedPointSnapshot(in: sketch, owner: "Sketch line dimension update")
        let fixedSides = try fixedRectangleSides(
            in: sketch,
            bounds: bounds,
            owner: "Sketch line dimension update"
        )
        let currentWidth = bounds.maxX - bounds.minX
        let currentHeight = bounds.maxY - bounds.minY
        if axis == .width,
           fixedSides.left,
           fixedSides.right,
           abs(currentWidth - resolvedLength) > 1.0e-12 {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line dimension update cannot resize a rectangle with both horizontal sides fixed."
            )
        }
        if axis == .height,
           fixedSides.bottom,
           fixedSides.top,
           abs(currentHeight - resolvedLength) > 1.0e-12 {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch line dimension update cannot resize a rectangle with both vertical sides fixed."
            )
        }
        let minX: CADExpression
        let maxX: CADExpression
        let minY: CADExpression
        let maxY: CADExpression
        switch axis {
        case .width:
            if fixedSides.right && fixedSides.left == false {
                minX = .subtract(.length(bounds.maxX, .meter), length)
                maxX = .length(bounds.maxX, .meter)
            } else {
                minX = .length(bounds.minX, .meter)
                maxX = .add(minX, length)
            }
            minY = .length(bounds.minY, .meter)
            maxY = .length(bounds.maxY, .meter)
        case .height:
            minX = .length(bounds.minX, .meter)
            maxX = .length(bounds.maxX, .meter)
            if fixedSides.top && fixedSides.bottom == false {
                minY = .subtract(.length(bounds.maxY, .meter), length)
                maxY = .length(bounds.maxY, .meter)
            } else {
                minY = .length(bounds.minY, .meter)
                maxY = .add(minY, length)
            }
        }
        let firstCorner = SketchPoint(
            x: minX,
            y: minY
        )
        let oppositeCorner = SketchPoint(
            x: maxX,
            y: maxY
        )
        try updateRectangleSketch(
            &sketch,
            firstCorner: firstCorner,
            oppositeCorner: oppositeCorner
        )
        try validateFixedPointSnapshot(
            fixedSnapshot,
            in: sketch,
            owner: "Sketch line dimension update"
        )
    }

    private func fixedRectangleSides(
        in sketch: Sketch,
        bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double),
        owner: String
    ) throws -> RectangleFixedSides {
        var sides = RectangleFixedSides()
        for snapshot in try fixedPointSnapshot(in: sketch, owner: owner) {
            if nearlyEqual(snapshot.x, bounds.minX, tolerance: 1.0e-9) {
                sides.left = true
            }
            if nearlyEqual(snapshot.x, bounds.maxX, tolerance: 1.0e-9) {
                sides.right = true
            }
            if nearlyEqual(snapshot.y, bounds.minY, tolerance: 1.0e-9) {
                sides.bottom = true
            }
            if nearlyEqual(snapshot.y, bounds.maxY, tolerance: 1.0e-9) {
                sides.top = true
            }
        }
        return sides
    }

    private func fixedPointSnapshot(
        in sketch: Sketch,
        owner: String
    ) throws -> [FixedSketchPointSnapshot] {
        var snapshots: [FixedSketchPointSnapshot] = []
        for constraint in sketch.constraints {
            guard case let .fixed(reference) = constraint,
                  let point = try resolvedPoint(reference, in: sketch, owner: owner) else {
                continue
            }
            snapshots.append(FixedSketchPointSnapshot(
                reference: reference,
                x: point.x,
                y: point.y
            ))
        }
        return snapshots
    }

    private func validateFixedPointSnapshot(
        _ snapshots: [FixedSketchPointSnapshot],
        in sketch: Sketch,
        owner: String
    ) throws {
        for snapshot in snapshots {
            guard let point = try resolvedPoint(snapshot.reference, in: sketch, owner: owner) else {
                continue
            }
            guard nearlyEqual(point.x, snapshot.x, tolerance: 1.0e-9),
                  nearlyEqual(point.y, snapshot.y, tolerance: 1.0e-9) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cannot move a fixed sketch point."
                )
            }
        }
    }

    private func resolvedPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (x: Double, y: Double)? {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(point, owner: owner)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(line.start, owner: owner)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(line.end, owner: owner)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .circle(circle) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(circle.center, owner: owner)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(arc.center, owner: owner)
        case let .arcStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.startAngle, owner: owner)
        case let .arcEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.endAngle, owner: owner)
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(spline.controlPoints[index], owner: owner)
        case .circleRadius, .arcRadius:
            return nil
        }
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    private func pointOnArc(
        _ arc: SketchArc,
        angle: CADExpression,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let center = try resolvedPoint(arc.center, owner: owner)
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let resolvedAngle = try resolvedAngleValue(angle, owner: "\(owner) arc angle")
        return (
            x: center.x + cos(resolvedAngle) * radius,
            y: center.y + sin(resolvedAngle) * radius
        )
    }

    private func invalidSketchPointReference(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references an unsupported sketch point."
        )
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
        case .arc(let arc):
            [arc.center]
        case .spline(let spline):
            spline.controlPoints
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
    public mutating func createPolySplineSurface(
        name: String,
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "PolySpline")
        let polySpline = PolySplineFeature(sourceMesh: sourceMesh, options: options)
        let analysis = PolySplineMeshAnalysisService().analyze(
            sourceMesh: sourceMesh,
            options: options
        )
        guard analysis.isSupported else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline requires a supported source mesh: \(analysis.failureMessage ?? "No supported patch candidate.")"
            )
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .polySpline(polySpline),
            outputs: [FeatureOutput(role: .sheet)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitPolySpline = false
        defer {
            if didCommitPolySpline == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: .polySpline,
                geometryRole: .surface,
                properties: ObjectPropertySet(values: [
                    "patch.count": .integer(analysis.supportedPatchCount),
                    "control.point.u": .integer(4),
                    "control.point.v": .integer(4),
                    "merge.patches": .boolean(options.mergePatches),
                    "interpolate.boundary": .boolean(options.interpolateBoundaryExactly),
                ]),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitPolySpline = true
        return featureID
    }

    public mutating func movePolySplineSurfaceVertex(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaZ: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let surfaceVertexEditor = PolySplineSurfaceVertexEditingService()
        let resolvedTarget = try PolySplineSurfaceVertexTarget.resolve(target, in: self)
        let delta = Vector3D(
            x: try resolvedLengthValue(deltaX, owner: "PolySpline surface vertex delta x"),
            y: try resolvedLengthValue(deltaY, owner: "PolySpline surface vertex delta y"),
            z: try resolvedLengthValue(deltaZ, owner: "PolySpline surface vertex delta z")
        )
        guard delta.length > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move requires a non-zero delta."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[resolvedTarget.featureID],
              case var .polySpline(polySpline) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface vertex move requires an existing PolySpline source feature."
            )
        }

        let sourceVertexIndex = try surfaceVertexEditor.sourceVertexIndex(
            for: resolvedTarget,
            in: polySpline,
            owner: "PolySpline surface vertex move"
        )
        guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface vertex move references a missing source mesh vertex."
            )
        }

        polySpline.sourceMesh.positions[sourceVertexIndex] =
            polySpline.sourceMesh.positions[sourceVertexIndex] + delta
        try polySpline.validate()
        try surfaceVertexEditor.validateTargetStillStable(
            resolvedTarget,
            sourceVertexIndex: sourceVertexIndex,
            in: polySpline,
            owner: "PolySpline surface vertex move"
        )

        var updatedCADDocument = cadDocument
        feature.operation = .polySpline(polySpline)

        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move produced invalid source geometry: \(error)."
            )
        }
    }

    public mutating func slidePolySplineSurfaceVertices(
        targets: [SelectionTarget],
        direction: PolySplineSurfaceVertexSlideDirection,
        distance: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let surfaceVertexEditor = PolySplineSurfaceVertexEditingService()
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex slide requires at least one generated topology vertex selection."
            )
        }
        let resolvedDistance = try resolvedLengthValue(
            distance,
            owner: "PolySpline surface vertex slide distance"
        )
        guard abs(resolvedDistance) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex slide requires a non-zero distance."
            )
        }

        struct SlideUpdate {
            var featureID: FeatureID
            var target: PolySplineSurfaceVertexTarget
            var sourceVertexIndex: Int
            var delta: Vector3D
        }
        struct SourceVertexKey: Hashable {
            var featureID: FeatureID
            var sourceVertexIndex: Int
        }

        var featuresByID: [FeatureID: FeatureNode] = [:]
        var polySplinesByID: [FeatureID: PolySplineFeature] = [:]
        var seenSourceVertices: Set<SourceVertexKey> = []
        var updates: [SlideUpdate] = []
        updates.reserveCapacity(targets.count)

        for target in targets {
            let resolvedTarget = try PolySplineSurfaceVertexTarget.resolve(target, in: self)
            let polySpline: PolySplineFeature
            if let cachedPolySpline = polySplinesByID[resolvedTarget.featureID] {
                polySpline = cachedPolySpline
            } else {
                guard let sourceFeature = cadDocument.designGraph.nodes[resolvedTarget.featureID],
                      case let .polySpline(sourcePolySpline) = sourceFeature.operation else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "PolySpline surface vertex slide requires an existing PolySpline source feature."
                    )
                }
                polySpline = sourcePolySpline
                featuresByID[resolvedTarget.featureID] = sourceFeature
                polySplinesByID[resolvedTarget.featureID] = sourcePolySpline
            }

            let sourceVertexIndex = try surfaceVertexEditor.sourceVertexIndex(
                for: resolvedTarget,
                in: polySpline,
                owner: "PolySpline surface vertex slide"
            )
            guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide references a missing source mesh vertex."
                )
            }
            let duplicateKey = SourceVertexKey(
                featureID: resolvedTarget.featureID,
                sourceVertexIndex: sourceVertexIndex
            )
            guard seenSourceVertices.insert(duplicateKey).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "PolySpline surface vertex slide cannot receive duplicate targets for the same source mesh vertex."
                )
            }

            let unitDirection = try surfaceVertexEditor.slideUnitVector(
                for: resolvedTarget,
                in: polySpline,
                direction: direction
            )
            updates.append(
                SlideUpdate(
                    featureID: resolvedTarget.featureID,
                    target: resolvedTarget,
                    sourceVertexIndex: sourceVertexIndex,
                    delta: Vector3D(
                        x: unitDirection.x * resolvedDistance,
                        y: unitDirection.y * resolvedDistance,
                        z: unitDirection.z * resolvedDistance
                    )
                )
            )
        }

        for update in updates {
            guard var polySpline = polySplinesByID[update.featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide lost a resolved source feature."
                )
            }
            polySpline.sourceMesh.positions[update.sourceVertexIndex] =
                polySpline.sourceMesh.positions[update.sourceVertexIndex] + update.delta
            polySplinesByID[update.featureID] = polySpline
        }

        for (featureID, polySpline) in polySplinesByID {
            try polySpline.validate()
            for update in updates where update.featureID == featureID {
                try surfaceVertexEditor.validateTargetStillStable(
                    update.target,
                    sourceVertexIndex: update.sourceVertexIndex,
                    in: polySpline,
                    owner: "PolySpline surface vertex slide"
                )
            }
        }

        var updatedCADDocument = cadDocument
        var replacementFeatures: [FeatureNode] = []
        for (featureID, feature) in featuresByID {
            guard let polySpline = polySplinesByID[featureID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide lost a resolved source mesh update."
                )
            }
            var updatedFeature = feature
            updatedFeature.operation = .polySpline(polySpline)
            replacementFeatures.append(updatedFeature)
        }

        let previousCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures(replacementFeatures)
            cadDocument = updatedCADDocument
            try validate(objectRegistry: objectRegistry)
        } catch {
            cadDocument = previousCADDocument
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex slide produced invalid source geometry: \(error)."
            )
        }
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
        guard try containsSupportedExtrudeProfile(source) else {
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

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitExtrude = false
        defer {
            if didCommitExtrude == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: name,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: .profile(profile),
                typeID: typeID,
                objectRegistry: objectRegistry
            )
        )
        try synchronizeObjectPropertiesFromSource(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        didCommitExtrude = true
        return featureID
    }

    @discardableResult
    public mutating func createRevolve(
        name: String,
        profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Revolve")
        let revolve = RevolveFeature(
            profile: profile,
            axis: axis,
            angle: angle,
            operation: .newBody
        )
        try revolve.validate()
        guard let source = cadDocument.designGraph.nodes[profile.featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Revolve profile must reference an existing sketch profile feature."
            )
        }
        guard try containsSupportedExtrudeProfile(source) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Revolve profile must reference a supported closed sketch profile."
            )
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .revolve(revolve),
            inputs: [FeatureInput(featureID: profile.featureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitRevolve = false
        defer {
            if didCommitRevolve == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: .profile(profile),
                typeID: nil,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Revolve produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommitRevolve = true
        return featureID
    }

    @discardableResult
    public mutating func createSweep(
        name: String,
        sections: [SweepSectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference] = [],
        targets: [SweepTargetReference] = [],
        options: SweepOptions = SweepOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Sweep")
        let sweep = SweepFeature(
            sections: sections,
            path: path,
            guides: guides,
            targets: targets,
            options: options
        )
        do {
            try sweep.validate()
            try validateSweepOptionQuantities(options)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep command is invalid: \(error)."
            )
        }
        for section in sections {
            switch section {
            case .profile(let profile):
                try requireSweepSourceProfileFeature(profile.featureID, owner: "Sweep profile")
            case .curve(let curve):
                try requireSweepSourceCurveFeature(curve.featureID, owner: "Sweep curve section")
            }
        }
        try requireSweepSourceCurveFeature(path.featureID, owner: "Sweep path")
        for guide in guides {
            try requireSweepSourceCurveFeature(guide.featureID, owner: "Sweep guide")
        }
        for target in targets {
            try requireSweepTargetBodyFeature(target.featureID, owner: "Sweep target")
        }

        let featureID = FeatureID()
        let inputs = sections.map { section in
            FeatureInput(featureID: section.featureID, role: section.inputRole)
        } + [
            FeatureInput(featureID: path.featureID, role: .path)
        ] + guides.map { guide in
            FeatureInput(featureID: guide.featureID, role: .guide)
        } + targets.map { target in
            FeatureInput(featureID: target.featureID, role: .target)
        }
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .sweep(sweep),
            inputs: inputs,
            outputs: [FeatureOutput(role: options.resultKind.featureOutputRole)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSweep = false
        defer {
            if didCommitSweep == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: sections.first.map(BodySourceSectionReference.init(sweepSection:)),
                typeID: nil,
                geometryRole: options.resultKind.objectGeometryRole,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommitSweep = true
        return featureID
    }

    private func containsSupportedExtrudeProfile(_ source: FeatureNode) throws -> Bool {
        guard case .sketch(let sketch) = source.operation else {
            return false
        }
        let parameters = try ParameterResolver().resolve(cadDocument.parameters)
        do {
            return try SketchProfileExtractor()
                .extractProfiles(
                    from: sketch,
                    sourceFeatureID: source.id,
                    parameters: parameters
                )
                .isEmpty == false
        } catch is SketchError {
            return false
        } catch is GeometryError {
            return false
        } catch is UnitError {
            return false
        }
    }

    private func requireSweepSourceProfileFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        guard let source = cadDocument.designGraph.nodes[featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference an existing sketch profile or curve feature."
            )
        }
        guard try containsSupportedExtrudeProfile(source) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference a supported closed sketch profile."
            )
        }
    }

    private func requireSweepSourceCurveFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        guard let source = cadDocument.designGraph.nodes[featureID],
              source.outputs.contains(where: { $0.role == .curve }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference an existing sketch curve feature."
            )
        }
        guard case .sketch = source.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference a sketch curve feature."
            )
        }
    }

    private func requireSweepTargetBodyFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        guard let source = cadDocument.designGraph.nodes[featureID],
              source.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference an existing body-producing feature."
            )
        }
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

    private mutating func appendFeature(_ feature: FeatureNode) throws {
        try cadDocument.appendFeature(feature)
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

    private func nextAvailableMetadataName(
        prefix: String,
        existingNames: inout Set<String>
    ) -> String {
        if existingNames.insert(prefix).inserted {
            return prefix
        }

        var index = 2
        while !existingNames.insert("\(prefix) \(index)").inserted {
            index += 1
        }
        return "\(prefix) \(index)"
    }

    private func requireRenderablePatternArrayDefinition(
        _ definitionID: ComponentDefinitionID,
        metadata: ProductMetadata
    ) throws -> ComponentDefinition {
        guard let definition = metadata.componentDefinitions[definitionID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern arrays must reference an existing component definition."
            )
        }
        guard ComponentDefinitionSceneResolver().containsRenderableSceneNode(
            in: definition,
            metadata: metadata
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern arrays require a component definition with at least one renderable scene node."
            )
        }
        return definition
    }

    private func synchronizePatternArrayOutputs(
        for sourceID: PatternArraySourceID,
        previousSource: PatternArraySource? = nil,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) throws {
        guard var source = metadata.patternArrays[sourceID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array regeneration requires an existing pattern source."
            )
        }
        guard let definition = metadata.componentDefinitions[source.definitionID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array regeneration requires an existing component definition."
            )
        }
        guard var rootNode = metadata.sceneNodes[source.rootSceneNodeID],
              rootNode.reference == nil,
              rootNode.object?.category == .group else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array regeneration requires an existing output group scene node."
            )
        }

        let transforms = try PatternArrayInstancePlanner().transforms(
            for: source.distribution,
            parameters: cadDocument.parameters,
            cadDocument: cadDocument
        )
        guard transforms.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern arrays must create at least one output instance."
            )
        }

        switch source.outputMode {
        case .componentInstance:
            try requireNoExternalFeatureDependents(
                of: Set(source.outputFeatureIDs),
                cadDocument: cadDocument,
                owner: "Component-instance pattern array conversion"
            )
            PatternArrayIndependentCopyBuilder().removeOutputs(
                source: source,
                metadata: &metadata,
                cadDocument: &cadDocument
            )
            source.outputSceneNodeIDs = []
            source.outputFeatureIDs = []
            source.definitionIdentity = nil
            try synchronizePatternArrayComponentInstanceOutputs(
                source: &source,
                rootNode: &rootNode,
                transforms: transforms,
                metadata: &metadata
            )
        case .independentCopy:
            removePatternArrayComponentInstanceOutputs(
                source: source,
                rootNode: rootNode,
                metadata: &metadata
            )
            let definitionIdentity = try PatternArrayDefinitionIdentityService().identity(
                for: definition,
                metadata: metadata,
                cadDocument: cadDocument
            )
            let reuseCandidate = previousSource ?? source
            let canReuseIndependentCopies = reuseCandidate.outputMode == .independentCopy &&
                reuseCandidate.definitionID == source.definitionID &&
                reuseCandidate.definitionIdentity == definitionIdentity
            if canReuseIndependentCopies {
                try synchronizePatternArrayIndependentCopyOutputs(
                    source: &source,
                    rootNode: &rootNode,
                    definition: definition,
                    transforms: transforms,
                    metadata: &metadata,
                    cadDocument: &cadDocument
                )
            } else {
                try requireNoExternalFeatureDependents(
                    of: Set(source.outputFeatureIDs),
                    cadDocument: cadDocument,
                    owner: "Independent-copy pattern array rebuild"
                )
                PatternArrayIndependentCopyBuilder().removeOutputs(
                    source: source,
                    metadata: &metadata,
                    cadDocument: &cadDocument
                )
                let result = try PatternArrayIndependentCopyBuilder().createOutputs(
                    name: source.name,
                    definition: definition,
                    transforms: transforms,
                    metadata: &metadata,
                    cadDocument: &cadDocument
                )
                source.outputSceneNodeIDs = result.outputSceneNodeIDs
                source.outputFeatureIDs = result.outputFeatureIDs
                rootNode.childIDs = result.outputSceneNodeIDs
                metadata.sceneNodes[source.rootSceneNodeID] = rootNode
            }
            source.outputInstanceIDs = []
            source.definitionIdentity = definitionIdentity
        }

        metadata.patternArrays[sourceID] = source
    }

    private func requireNoExternalFeatureDependents(
        of removedFeatureIDs: Set<FeatureID>,
        cadDocument: CADDocument,
        owner: String
    ) throws {
        guard !removedFeatureIDs.isEmpty else {
            return
        }
        let dependentFeatureIDs = cadDocument.designGraph.order.filter { featureID in
            guard !removedFeatureIDs.contains(featureID),
                  let feature = cadDocument.designGraph.nodes[featureID] else {
                return false
            }
            return feature.inputs.contains { removedFeatureIDs.contains($0.featureID) }
        }
        guard dependentFeatureIDs.isEmpty else {
            let dependentList = dependentFeatureIDs
                .prefix(3)
                .map(\.description)
                .joined(separator: ", ")
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot remove independent-copy output features while downstream features depend on them. Delete or detach the dependent features first: \(dependentList)."
            )
        }
    }

    private func synchronizePatternArrayIndependentCopyOutputs(
        source: inout PatternArraySource,
        rootNode: inout SceneNode,
        definition: ComponentDefinition,
        transforms: [Transform3D],
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) throws {
        let builder = PatternArrayIndependentCopyBuilder()
        let reusedCount = min(source.outputSceneNodeIDs.count, transforms.count)
        let reusableOutputSceneNodeIDs = Array(source.outputSceneNodeIDs.prefix(reusedCount))
        let staleOutputSceneNodeIDs = Array(source.outputSceneNodeIDs.dropFirst(reusedCount))
        let ownedFeatureIDs = Set(source.outputFeatureIDs)

        var reusedFeatureIDs: Set<FeatureID> = []
        reusedFeatureIDs.reserveCapacity(ownedFeatureIDs.count)
        for (index, outputSceneNodeID) in reusableOutputSceneNodeIDs.enumerated() {
            guard var outputNode = metadata.sceneNodes[outputSceneNodeID],
                  outputNode.reference == nil,
                  outputNode.object?.category == .group else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Independent-copy pattern array reuse requires existing group output scene nodes."
                )
            }
            outputNode.name = "\(source.name) \(index + 1)"
            outputNode.localTransform = transforms[index]
            metadata.sceneNodes[outputSceneNodeID] = outputNode
            let outputFeatureIDs = builder.outputFeatureClosure(
                rootedAt: outputSceneNodeID,
                metadata: metadata,
                cadDocument: cadDocument
            )
            guard !outputFeatureIDs.isEmpty,
                  outputFeatureIDs.isSubset(of: ownedFeatureIDs) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Independent-copy pattern array reuse requires owned output feature closures."
                )
            }
            reusedFeatureIDs.formUnion(outputFeatureIDs)
        }

        var staleFeatureIDs: Set<FeatureID> = []
        for staleOutputSceneNodeID in staleOutputSceneNodeIDs {
            staleFeatureIDs.formUnion(
                builder.outputFeatureClosure(
                    rootedAt: staleOutputSceneNodeID,
                    metadata: metadata,
                    cadDocument: cadDocument
                )
            )
        }
        staleFeatureIDs.formIntersection(ownedFeatureIDs.subtracting(reusedFeatureIDs))
        try requireNoExternalFeatureDependents(
            of: staleFeatureIDs,
            cadDocument: cadDocument,
            owner: "Independent-copy pattern array tail removal"
        )
        builder.removeOutputs(
            rootedAt: staleOutputSceneNodeIDs,
            featureIDs: staleFeatureIDs,
            metadata: &metadata,
            cadDocument: &cadDocument
        )

        let appendedTransforms = Array(transforms.dropFirst(reusedCount))
        let appendedResult: PatternArrayIndependentCopyBuildResult
        if appendedTransforms.isEmpty {
            appendedResult = PatternArrayIndependentCopyBuildResult(
                outputSceneNodeIDs: [],
                outputFeatureIDs: []
            )
        } else {
            appendedResult = try builder.createOutputs(
                name: source.name,
                definition: definition,
                transforms: appendedTransforms,
                startingOutputIndex: reusedCount,
                metadata: &metadata,
                cadDocument: &cadDocument
            )
        }

        source.outputSceneNodeIDs = reusableOutputSceneNodeIDs + appendedResult.outputSceneNodeIDs
        let nextFeatureIDs = reusedFeatureIDs.union(appendedResult.outputFeatureIDs)
        source.outputFeatureIDs = builder.orderedFeatureIDs(
            nextFeatureIDs,
            cadDocument: cadDocument
        )
        rootNode.childIDs = source.outputSceneNodeIDs
        metadata.sceneNodes[source.rootSceneNodeID] = rootNode
    }

    private func synchronizePatternArrayComponentInstanceOutputs(
        source: inout PatternArraySource,
        rootNode: inout SceneNode,
        transforms: [Transform3D],
        metadata: inout ProductMetadata
    ) throws {
        let previousOutputIDs = source.outputInstanceIDs
        let reusableOutputIDs = Array(previousOutputIDs.prefix(transforms.count))
        let reusableOutputIDSet = Set(reusableOutputIDs)
        var usedInstanceNames = Set(
            metadata.componentInstances.values.compactMap { instance in
                previousOutputIDs.contains(instance.id)
                    ? nil
                    : instance.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        let existingChildIDsByInstanceID = patternArrayChildSceneNodeIDsByInstanceID(
            rootNode: rootNode,
            metadata: metadata
        )

        var nextOutputIDs: [ComponentInstanceID] = []
        var nextChildIDs: [SceneNodeID] = []
        nextOutputIDs.reserveCapacity(transforms.count)
        nextChildIDs.reserveCapacity(transforms.count)
        for (index, transform) in transforms.enumerated() {
            let instanceID = index < reusableOutputIDs.count
                ? reusableOutputIDs[index]
                : ComponentInstanceID()
            let instanceName: String
            if let existingInstance = metadata.componentInstances[instanceID] {
                instanceName = existingInstance.name
                usedInstanceNames.insert(existingInstance.name.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                instanceName = nextAvailableMetadataName(
                    prefix: "\(source.name) \(index + 1)",
                    existingNames: &usedInstanceNames
                )
            }

            var instance = metadata.componentInstances[instanceID] ?? ComponentInstance(
                id: instanceID,
                definitionID: source.definitionID,
                name: instanceName
            )
            instance.definitionID = source.definitionID
            instance.name = instanceName
            instance.localTransform = transform
            metadata.componentInstances[instanceID] = instance
            nextOutputIDs.append(instanceID)

            let sceneNodeID = existingChildIDsByInstanceID[instanceID] ?? SceneNodeID()
            var sceneNode = metadata.sceneNodes[sceneNodeID] ?? SceneNode(id: sceneNodeID, name: instanceName)
            sceneNode.name = instanceName
            sceneNode.reference = .componentInstance(instanceID)
            sceneNode.object = .componentInstance(instanceID)
            sceneNode.localTransform = .identity
            metadata.sceneNodes[sceneNodeID] = sceneNode
            nextChildIDs.append(sceneNodeID)
        }

        let nextOutputIDSet = Set(nextOutputIDs)
        for removedInstanceID in Set(previousOutputIDs).subtracting(nextOutputIDSet) {
            metadata.componentInstances.removeValue(forKey: removedInstanceID)
            if let removedSceneNodeID = existingChildIDsByInstanceID[removedInstanceID] {
                metadata.sceneNodes.removeValue(forKey: removedSceneNodeID)
            }
        }
        for removedChildID in Set(rootNode.childIDs).subtracting(Set(nextChildIDs)) {
            if let componentInstanceID = metadata.sceneNodes[removedChildID]?.reference?.componentInstanceID,
               !reusableOutputIDSet.contains(componentInstanceID) {
                metadata.componentInstances.removeValue(forKey: componentInstanceID)
            }
            metadata.sceneNodes.removeValue(forKey: removedChildID)
        }

        source.outputInstanceIDs = nextOutputIDs
        rootNode.childIDs = nextChildIDs
        metadata.sceneNodes[source.rootSceneNodeID] = rootNode
    }

    private func removePatternArrayComponentInstanceOutputs(
        source: PatternArraySource,
        rootNode: SceneNode,
        metadata: inout ProductMetadata
    ) {
        for instanceID in source.outputInstanceIDs {
            metadata.componentInstances.removeValue(forKey: instanceID)
        }
        for childID in rootNode.childIDs {
            if let componentInstanceID = metadata.sceneNodes[childID]?.reference?.componentInstanceID,
               source.outputInstanceIDs.contains(componentInstanceID) {
                metadata.componentInstances.removeValue(forKey: componentInstanceID)
            }
            metadata.sceneNodes.removeValue(forKey: childID)
        }
    }

    private func materializedPatternArrayOutputsForExplode(
        source: PatternArraySource,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) throws -> PatternArrayExplodeResult {
        guard var rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Pattern array explode requires an existing output group scene node."
            )
        }
        switch source.outputMode {
        case .componentInstance:
            let transforms = try source.outputInstanceIDs.map { instanceID -> Transform3D in
                guard let instance = metadata.componentInstances[instanceID] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Pattern array explode requires existing output component instances."
                    )
                }
                return instance.localTransform
            }
            guard let definition = metadata.componentDefinitions[source.definitionID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Pattern array explode requires an existing component definition."
                )
            }
            removePatternArrayComponentInstanceOutputs(
                source: source,
                rootNode: rootNode,
                metadata: &metadata
            )
            let result = try PatternArrayIndependentCopyBuilder().createOutputs(
                name: source.name,
                definition: definition,
                transforms: transforms,
                metadata: &metadata,
                cadDocument: &cadDocument
            )
            rootNode.childIDs = result.outputSceneNodeIDs
            metadata.sceneNodes[source.rootSceneNodeID] = rootNode
            return PatternArrayExplodeResult(
                componentInstanceIDs: source.outputInstanceIDs,
                sceneNodeIDs: result.outputSceneNodeIDs,
                featureIDs: result.outputFeatureIDs
            )
        case .independentCopy:
            return PatternArrayExplodeResult(
                sceneNodeIDs: source.outputSceneNodeIDs,
                featureIDs: source.outputFeatureIDs
            )
        }
    }

    private func patternArrayChildSceneNodeIDsByInstanceID(
        rootNode: SceneNode,
        metadata: ProductMetadata
    ) -> [ComponentInstanceID: SceneNodeID] {
        var sceneNodeIDsByInstanceID: [ComponentInstanceID: SceneNodeID] = [:]
        for childID in rootNode.childIDs {
            guard let componentInstanceID = metadata.sceneNodes[childID]?.reference?.componentInstanceID else {
                continue
            }
            sceneNodeIDsByInstanceID[componentInstanceID] = childID
        }
        return sceneNodeIDsByInstanceID
    }

    private func patternArraySourceID(
        owningOutputInstance componentInstanceID: ComponentInstanceID
    ) -> PatternArraySourceID? {
        productMetadata.patternArrays.first { _, source in
            source.outputInstanceIDs.contains(componentInstanceID)
        }?.key
    }

    private func patternArraySourceID(
        containingGeneratedOutputSceneNode sceneNodeID: SceneNodeID
    ) -> PatternArraySourceID? {
        productMetadata.patternArrays.first { _, source in
            guard let rootNode = productMetadata.sceneNodes[source.rootSceneNodeID] else {
                return false
            }
            return rootNode.childIDs.contains { outputSceneNodeID in
                sceneSubtree(
                    outputSceneNodeID,
                    contains: sceneNodeID
                )
            }
        }?.key
    }

    private func patternArraySourceID(
        containingOutputSceneNode sceneNodeID: SceneNodeID
    ) -> PatternArraySourceID? {
        productMetadata.patternArrays.first { _, source in
            guard let rootNode = productMetadata.sceneNodes[source.rootSceneNodeID] else {
                return false
            }
            if source.rootSceneNodeID == sceneNodeID {
                return true
            }
            return rootNode.childIDs.contains { outputSceneNodeID in
                sceneSubtree(
                    outputSceneNodeID,
                    contains: sceneNodeID
                )
            }
        }?.key
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID
    ) -> Bool {
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        return sceneSubtree(
            rootSceneNodeID,
            contains: targetSceneNodeID,
            visitedSceneNodeIDs: &visitedSceneNodeIDs
        )
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        visitedSceneNodeIDs: inout Set<SceneNodeID>
    ) -> Bool {
        guard visitedSceneNodeIDs.insert(rootSceneNodeID).inserted else {
            return false
        }
        if rootSceneNodeID == targetSceneNodeID {
            return true
        }
        guard let sceneNode = productMetadata.sceneNodes[rootSceneNodeID] else {
            return false
        }
        return sceneNode.childIDs.contains { childID in
            sceneSubtree(
                childID,
                contains: targetSceneNodeID,
                visitedSceneNodeIDs: &visitedSceneNodeIDs
            )
        }
    }

    private struct EditableBodyTargetResolution {
        var sceneNodeID: SceneNodeID
        var sceneNode: SceneNode
        var featureID: FeatureID
        var target: SelectionTarget
    }

    private func editableBodyTargetResolution(
        for target: SelectionTarget,
        operationName: String
    ) throws -> EditableBodyTargetResolution {
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              let reference = sceneNode.reference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body scene node."
            )
        }
        if reference.kind == .body,
           let featureID = reference.featureID {
            return EditableBodyTargetResolution(
                sceneNodeID: target.sceneNodeID,
                sceneNode: sceneNode,
                featureID: featureID,
                target: target
            )
        }
        guard reference.kind == .componentInstance,
              let componentInstanceID = reference.componentInstanceID,
              let instance = productMetadata.componentInstances[componentInstanceID],
              let definition = productMetadata.componentDefinitions[instance.definitionID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body scene node."
            )
        }
        let preferredFeatureID = try sourceFeatureID(
            for: target.component,
            operationName: operationName
        )
        let bodySceneNodeIDs = ComponentDefinitionSceneResolver().bodySceneNodeIDs(
            in: definition,
            preferredFeatureID: preferredFeatureID,
            metadata: productMetadata
        )
        guard let sourceSceneNodeID = bodySceneNodeIDs.first,
              bodySceneNodeIDs.count == 1,
              let sourceSceneNode = productMetadata.sceneNodes[sourceSceneNodeID],
              let sourceFeatureID = sourceSceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) component instance target must resolve to exactly one source body scene node."
            )
        }
        return EditableBodyTargetResolution(
            sceneNodeID: sourceSceneNodeID,
            sceneNode: sourceSceneNode,
            featureID: sourceFeatureID,
            target: SelectionTarget(
                sceneNodeID: sourceSceneNodeID,
                component: target.component
            )
        )
    }

    private func sourceFeatureID(
        for component: SelectionComponent,
        operationName: String
    ) throws -> FeatureID? {
        let componentID: SelectionComponentID?
        switch component {
        case .face(let id), .edge(let id), .vertex(let id):
            componentID = id
        case .object, .sketchEntity, .region:
            componentID = nil
        }
        guard let persistentName = componentID?.generatedTopologyPersistentName else {
            return nil
        }
        let parsedName = try GeneratedTopologyPersistentNameParser().parse(
            persistentName,
            operationName: operationName
        )
        for component in parsedName.components {
            if case .feature(let featureID) = component {
                return featureID
            }
        }
        return nil
    }

}

private extension SweepResultKind {
    var featureOutputRole: FeaturePort {
        switch self {
        case .solid:
            .body
        case .sheet:
            .sheet
        }
    }

    var objectGeometryRole: ObjectDescriptor.GeometryRole {
        switch self {
        case .solid:
            .solid
        case .sheet:
            .surface
        }
    }
}

private extension OffsetCurveGapFill {
    var faceLoopOffsetGapFill: FaceLoopOffsetGapFill {
        switch self {
        case .round:
            .round
        case .linear:
            .linear
        case .natural:
            .natural
        }
    }

    var edgeOffsetGapFill: EdgeOffsetGapFill {
        switch self {
        case .round:
            .round
        case .linear:
            .linear
        case .natural:
            .natural
        }
    }
}

private enum EditableBodyFace: Equatable {
    case front
    case back
    case top
    case bottom
    case left
    case right
    case side
}

private enum EditableBodyEdge: Equatable, Hashable {
    case leftBottom
    case rightBottom
    case rightTop
    case leftTop
}

private enum EditableBodyVertex: Equatable, Hashable {
    case bottomLeft
    case bottomRight
    case topRight
    case topLeft
}

private enum RectangleSideDimensionAxis: Equatable {
    case width
    case height
}

private struct RectangleFixedSides: Equatable {
    var left = false
    var right = false
    var bottom = false
    var top = false
}

private struct FixedSketchPointSnapshot: Equatable {
    var reference: SketchReference
    var x: Double
    var y: Double
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

    var arc: SketchArc? {
        if case .arc(let arc) = self {
            return arc
        }
        return nil
    }

    var spline: SketchSpline? {
        if case .spline(let spline) = self {
            return spline
        }
        return nil
    }
}
