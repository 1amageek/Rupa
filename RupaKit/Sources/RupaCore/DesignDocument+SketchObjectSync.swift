import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    mutating func commitSketchEntityEdit(
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

    mutating func synchronizeSketchObjectProperties(
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

    mutating func setSketchObjectType(
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

    mutating func markSketchObjectAsSourceEdited(featureID: FeatureID) throws {
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
}
