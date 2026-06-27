import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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

    func offsetExtrudeDepth(
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

    mutating func offsetCylinderFace(
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

    mutating func translateSceneNode(
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
}
