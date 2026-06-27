import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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

    func resolvedExtrudedBodyDimensions(
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
}
