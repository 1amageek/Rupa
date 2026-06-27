import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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

        guard sceneNodeID != nil else {
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

        guard sceneNodeID != nil else {
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
}
