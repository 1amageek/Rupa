import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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
}
