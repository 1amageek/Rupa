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
            nextSketch = try movedRectangleProfileSketch(
                sketch,
                corner: vertex,
                deltaXMeters: deltaXMeters,
                deltaYMeters: deltaYMeters,
                operationName: "Vertex move"
            )
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
            try updatedCADDocument.replaceFeatures([profileFeature, feature], tolerance: modelingSettings.tolerance)
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
