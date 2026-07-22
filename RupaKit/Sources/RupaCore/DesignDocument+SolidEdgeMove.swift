import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func moveBodyEdge(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Body edge move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Body edge move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Body edge move delta must not be zero."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: "Body edge move"
        )

        if case .edge(let componentID) = resolvedTarget.target.component,
           componentID.isStableTopology {
            if try moveGeneratedProfileEdge(
                target: resolvedTarget.target,
                bodyFeatureID: resolvedTarget.featureID,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            ) {
                return
            }
        }

        try moveBodyCornerEdge(
            resolvedTarget: resolvedTarget,
            deltaX: deltaX,
            deltaY: deltaY,
            objectRegistry: objectRegistry
        )
    }

    private mutating func moveGeneratedProfileEdge(
        target: SelectionTarget,
        bodyFeatureID: FeatureID,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws -> Bool {
        let resolved: [SketchDimensionTargetResolver.ResolvedTarget]
        do {
            resolved = try SketchDimensionTargetResolver().resolve(
                document: self,
                targets: [target],
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError where error.code == .referenceUnresolved {
            return false
        }
        guard let source = resolved.first,
              resolved.count == 1 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Body edge move could not resolve one editable source profile edge."
            )
        }

        var candidate = self
        switch source.entity.entityKind {
        case "line":
            try candidate.translateSketchLine(
                target: source.editTarget,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            )
        case "circle":
            try candidate.moveSketchEntityPoint(
                target: source.editTarget,
                handle: .circleCenter,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            )
        case "arc":
            try candidate.moveGeneratedProfileArcEdge(
                target: source.editTarget,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Body edge move currently supports generated line, circle, and line-arc-line arc profile edges."
            )
        }

        do {
            try candidate.validateEditableBodyCandidate(
                candidate.cadDocument,
                operationName: "Body edge move",
                objectRegistry: objectRegistry
            )
        } catch {
            throw error
        }
        cadDocument = candidate.cadDocument
        productMetadata = candidate.productMetadata
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        if isPrimitiveExtrudeBody(featureID: bodyFeatureID) {
            try synchronizeObjectPropertiesFromSource(
                featureID: bodyFeatureID,
                objectRegistry: objectRegistry
            )
        } else {
            try markBodyObjectAsSourceEditedSolid(featureID: bodyFeatureID)
        }
        return true
    }

    private mutating func moveGeneratedProfileArcEdge(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let selection = try editableSketchEntity(
            for: target,
            operationName: "Body edge arc move"
        )
        guard case .arc = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Body edge arc move requires an arc source profile edge."
            )
        }
        guard let nextSketch = try profileArcMoveSketch(
            featureID: selection.featureID,
            entityID: selection.entityID,
            sketch: selection.sketch,
            deltaX: deltaX,
            deltaY: deltaY
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Body edge arc move requires a normal extrude line-arc-line profile corner."
            )
        }

        var profileFeature = selection.feature
        profileFeature.operation = .sketch(nextSketch)
        do {
            try cadDocument.replaceFeature(
                profileFeature,
                tolerance: modelingSettings.tolerance
            )
            try synchronizeSketchObjectProperties(
                featureID: selection.featureID,
                sketch: nextSketch,
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Body edge arc move produced invalid sketch geometry: \(error)."
            )
        }
    }

    private mutating func moveBodyCornerEdge(
        resolvedTarget: EditableBodyTargetResolution,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let featureID = resolvedTarget.featureID
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation,
              var profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Body edge move requires an editable sketch profile."
            )
        }

        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Body edge move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Body edge move delta Y")
        let nextSketch: Sketch
        let preservesObjectProperties: Bool
        if isRectangleProfile(sketch) {
            let edge = try editableBodyEdge(
                for: resolvedTarget.target,
                operationName: "Body edge move",
                objectRegistry: objectRegistry
            )
            guard var bounds = try resolvedSketchBounds2D(sketch) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Body edge move requires a finite rectangle profile."
                )
            }

            switch edge {
            case .leftBottom:
                bounds.minX += deltaXMeters
                bounds.minY += deltaYMeters
            case .rightBottom:
                bounds.maxX += deltaXMeters
                bounds.minY += deltaYMeters
            case .rightTop:
                bounds.maxX += deltaXMeters
                bounds.maxY += deltaYMeters
            case .leftTop:
                bounds.minX += deltaXMeters
                bounds.maxY += deltaYMeters
            }

            guard bounds.maxX - bounds.minX > 1.0e-9,
                  bounds.maxY - bounds.minY > 1.0e-9 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Body edge move would collapse the rectangle profile."
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
                operationName: "Body edge move"
            )
            let index = try profileLoopVertexIndex(
                for: resolvedTarget.target,
                profileLoop: profileLoop,
                sketchPlane: sketch.plane,
                expectedKind: .edge,
                operationName: "Body edge move",
                objectRegistry: objectRegistry
            )
            nextSketch = try profileLoop.movedVertexSketch(
                targetVertexIndex: index,
                deltaX: deltaXMeters,
                deltaY: deltaYMeters,
                operationName: "Body edge move"
            )
            preservesObjectProperties = false
        }

        profileFeature.operation = .sketch(nextSketch)
        feature.operation = .extrude(extrude)

        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeatures(
                [profileFeature, feature],
                tolerance: modelingSettings.tolerance
            )
            try validateEditableBodyCandidate(
                updatedCADDocument,
                operationName: "Body edge move",
                objectRegistry: objectRegistry
            )
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Body edge move produced invalid geometry: \(error)."
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

    private func isPrimitiveExtrudeBody(featureID: FeatureID) -> Bool {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .extrude(extrude) = feature.operation,
              let profileFeature = cadDocument.designGraph.nodes[extrude.profile.featureID],
              case let .sketch(sketch) = profileFeature.operation else {
            return false
        }
        return isRectangleProfile(sketch) || singleCircleEntry(in: sketch) != nil
    }
}
