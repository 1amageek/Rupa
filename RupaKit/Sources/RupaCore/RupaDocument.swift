import Foundation
import SwiftCAD

public struct RupaDocument: Identifiable, Sendable {
    public var cadDocument: CADDocument
    public var displayUnit: LengthDisplayUnit
    public var ruler: RulerConfiguration
    public var productMetadata: RupaProductMetadata

    public var id: DocumentID {
        cadDocument.id
    }

    public init(
        cadDocument: CADDocument,
        displayUnit: LengthDisplayUnit,
        ruler: RulerConfiguration,
        productMetadata: RupaProductMetadata = .empty()
    ) {
        self.cadDocument = cadDocument
        self.displayUnit = displayUnit
        self.ruler = ruler
        self.productMetadata = productMetadata
    }

    public static func empty(named name: String = "Untitled") -> RupaDocument {
        let unit: LengthDisplayUnit = .millimeter
        return RupaDocument(
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
            throw RupaError(
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
            throw RupaError(
                code: .referenceUnresolved,
                message: "Parameter \(name) is still referenced: \(error)."
            )
        }
        cadDocument = updatedCADDocument
    }

    @discardableResult
    public mutating func createComponentDefinition(
        name: String,
        rootSceneNodeIDs: [RupaSceneNodeID] = []
    ) throws -> RupaComponentDefinitionID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Component definition"
        )
        guard productMetadata.componentDefinitions.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw RupaError(
                code: .commandInvalid,
                message: "Component definition names must be unique."
            )
        }
        for rootSceneNodeID in rootSceneNodeIDs {
            guard productMetadata.sceneNodes[rootSceneNodeID] != nil else {
                throw RupaError(
                    code: .referenceUnresolved,
                    message: "Component definition root scene nodes must exist."
                )
            }
        }

        let definition = RupaComponentDefinition(
            name: trimmedName,
            rootSceneNodeIDs: rootSceneNodeIDs
        )
        productMetadata.componentDefinitions[definition.id] = definition
        try productMetadata.validate(against: cadDocument)
        return definition.id
    }

    @discardableResult
    public mutating func createComponentInstance(
        name: String,
        definitionID: RupaComponentDefinitionID,
        localTransform: Transform3D = .identity
    ) throws -> RupaComponentInstanceID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Component instance"
        )
        guard productMetadata.componentDefinitions[definitionID] != nil else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Component instances must reference an existing component definition."
            )
        }
        guard productMetadata.componentInstances.values.allSatisfy({
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) != trimmedName
        }) else {
            throw RupaError(
                code: .commandInvalid,
                message: "Component instance names must be unique."
            )
        }

        let instance = RupaComponentInstance(
            definitionID: definitionID,
            name: trimmedName,
            localTransform: localTransform
        )
        productMetadata.componentInstances[instance.id] = instance
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .componentInstance(instance.id)
        )
        try productMetadata.validate(against: cadDocument)
        return instance.id
    }

    public mutating func setSceneNodeVisibility(
        id: RupaSceneNodeID,
        isVisible: Bool
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Scene node visibility requires an existing scene node."
            )
        }
        node.isVisible = isVisible
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument)
    }

    public mutating func setSceneNodeLock(
        id: RupaSceneNodeID,
        isLocked: Bool
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Scene node lock requires an existing scene node."
            )
        }
        node.isLocked = isLocked
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument)
    }

    public mutating func setSceneNodeTransform(
        id: RupaSceneNodeID,
        localTransform: Transform3D
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Scene node transform requires an existing scene node."
            )
        }
        try localTransform.validate()
        node.localTransform = localTransform
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument)
    }

    public mutating func setSceneNodeMaterial(
        id: RupaSceneNodeID,
        materialID: MaterialID?
    ) throws {
        guard var node = productMetadata.sceneNodes[id] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Scene node material requires an existing scene node."
            )
        }
        if let materialID,
           productMetadata.materialLibrary.materials[materialID] == nil {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Scene node material requires an existing material."
            )
        }
        node.materialID = materialID
        productMetadata.sceneNodes[id] = node
        try productMetadata.validate(against: cadDocument)
    }

    public mutating func setComponentInstanceVisibility(
        id: RupaComponentInstanceID,
        isVisible: Bool
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Component instance visibility requires an existing component instance."
            )
        }
        instance.isVisible = isVisible
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument)
    }

    public mutating func setComponentInstanceLock(
        id: RupaComponentInstanceID,
        isLocked: Bool
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Component instance lock requires an existing component instance."
            )
        }
        instance.isLocked = isLocked
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument)
    }

    public mutating func setComponentInstanceTransform(
        id: RupaComponentInstanceID,
        localTransform: Transform3D
    ) throws {
        guard var instance = productMetadata.componentInstances[id] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Component instance transform requires an existing component instance."
            )
        }
        try localTransform.validate()
        instance.localTransform = localTransform
        productMetadata.componentInstances[id] = instance
        try productMetadata.validate(against: cadDocument)
    }

    @discardableResult
    public mutating func createSectionPlane(name: String) throws -> RupaSceneNodeID {
        let trimmedName = try normalizedMetadataName(
            name,
            owner: "Section plane"
        )
        let sceneNodeID = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .construction
        )
        try productMetadata.validate(against: cadDocument)
        return sceneNodeID
    }

    @discardableResult
    public mutating func createLineSketch(
        name: String,
        plane: SketchPlane,
        start: SketchPoint,
        end: SketchPoint
    ) throws -> FeatureID {
        var builder = SketchBuilder(on: plane)
        _ = builder.line(from: start, to: end)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch
        )
    }

    @discardableResult
    public mutating func createCircleSketch(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression
    ) throws -> FeatureID {
        let resolvedRadius = try resolvedLengthValue(radius, owner: "Circle radius")
        guard resolvedRadius > 0.0 else {
            throw RupaError(
                code: .commandInvalid,
                message: "Circle sketch radius must be greater than zero."
            )
        }

        var builder = SketchBuilder(on: plane)
        builder.circle(center: center, radius: radius)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch
        )
    }

    @discardableResult
    public mutating func createRectangleSketch(
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression
    ) throws -> FeatureID {
        var builder = SketchBuilder(on: plane)
        builder.rectangle(width: width, height: height)
        let sketch = builder.build()
        return try appendSketchFeature(
            name: name,
            sketch: sketch
        )
    }

    @discardableResult
    public mutating func createRectangleSketchFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) throws -> FeatureID {
        let firstX = try resolvedLengthValue(firstCorner.x, owner: "Rectangle first corner x")
        let firstY = try resolvedLengthValue(firstCorner.y, owner: "Rectangle first corner y")
        let oppositeX = try resolvedLengthValue(oppositeCorner.x, owner: "Rectangle opposite corner x")
        let oppositeY = try resolvedLengthValue(oppositeCorner.y, owner: "Rectangle opposite corner y")
        guard firstX != oppositeX, firstY != oppositeY else {
            throw RupaError(
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
            sketch: sketch
        )
    }

    public mutating func addSketchConstraint(
        featureID: FeatureID,
        constraint: SketchConstraint
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Sketch constraint requires an existing sketch feature."
            )
        }
        guard case var .sketch(sketch) = feature.operation else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Sketch constraint requires a sketch feature."
            )
        }
        guard !sketch.constraints.contains(constraint) else {
            throw RupaError(
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
            throw RupaError(
                code: .referenceUnresolved,
                message: "Sketch constraint references invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try productMetadata.validate(against: cadDocument)
    }

    public mutating func setExtrudeDistance(
        featureID: FeatureID,
        distance: CADExpression
    ) throws {
        _ = try resolvedLengthValue(distance, owner: "Extrude distance")
        guard var feature = cadDocument.designGraph.nodes[featureID] else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Extrude distance requires an existing feature."
            )
        }
        guard case var .extrude(extrude) = feature.operation else {
            throw RupaError(
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
            throw RupaError(
                code: .referenceUnresolved,
                message: "Extrude distance produced invalid geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try productMetadata.validate(against: cadDocument)
    }

    @discardableResult
    private mutating func appendSketchFeature(
        name: String,
        sketch: Sketch
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
            reference: .sketch(featureID)
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
            throw RupaError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw RupaError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    @discardableResult
    public mutating func extrudeProfile(
        name: String,
        profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection
    ) throws -> FeatureID {
        try profile.validate()
        guard let source = cadDocument.designGraph.nodes[profile.featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Extrude profile must reference an existing sketch profile feature."
            )
        }
        guard source.containsSupportedExtrudeProfile else {
            throw RupaError(
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
            reference: .body(featureID)
        )
        appendFeature(feature)
        cadDocument.designGraph.dependencies.append(
            DependencyEdge(source: profile.featureID, target: featureID)
        )
        return featureID
    }

    public mutating func createExtrudedRectangle(
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    ) throws {
        let sketchFeatureID = try createRectangleSketch(
            name: "\(name) Sketch",
            plane: plane,
            width: width,
            height: height
        )
        try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction
        )
    }

    public mutating func createExtrudedRectangleFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression,
        direction: ExtrudeDirection
    ) throws {
        let sketchFeatureID = try createRectangleSketchFromCorners(
            name: "\(name) Sketch",
            plane: plane,
            firstCorner: firstCorner,
            oppositeCorner: oppositeCorner
        )
        try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction
        )
    }

    public mutating func createExtrudedCircle(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection
    ) throws {
        let sketchFeatureID = try createCircleSketch(
            name: "\(name) Sketch",
            plane: plane,
            center: center,
            radius: radius
        )
        try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction
        )
    }

    public func validate() throws {
        try cadDocument.validate()
        try ruler.validate()
        guard ruler.displayUnit == displayUnit else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Document ruler display unit must match the document display unit."
            )
        }
        try productMetadata.validate(against: cadDocument)
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
            throw RupaError(
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
