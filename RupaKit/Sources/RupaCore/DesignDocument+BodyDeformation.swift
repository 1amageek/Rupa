import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Deform Solid and Sheet: each selected body is carried from the reference face onto the
    /// target face by `options` (see `CurveDeformationOptions`) through one Swift-CAD `wrap` per
    /// body, as one step. Each face is read where its object is displayed, placed in the body's
    /// frame. Without Keep Tools the deformed body takes over the body's object; with it the body
    /// stays and the deformed copy is shown beside it. Returns the Wraps, a body holding a picked face
    /// last.
    @discardableResult
    public mutating func deformBodies(
        targets: [SceneNodeID],
        referenceFace: SelectionTarget,
        targetFace: SelectionTarget,
        options: CurveDeformationOptions,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID] {
        let owner = "Deform Solid and Sheet"
        guard !targets.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "\(owner) needs at least one selected body.")
        }
        guard Set(targets).count == targets.count else {
            throw EditorError(code: .commandInvalid, message: "\(owner) received the same body more than once.")
        }
        try options.validate()
        let wrapOptions = options.wrapOptions
        do {
            try wrapOptions.validate()
        } catch {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error)")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        func stableFace(_ face: SelectionTarget, role: String) throws -> StableSubshapeReference {
            guard case .face = face.component,
                  let entry = topology.entries.first(where: { $0.kind == .face && $0.selectionTarget() == face }),
                  let reference = entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "\(owner) \(role) face is not a face of an evaluated body.")
            }
            return reference
        }
        let reference = try stableFace(referenceFace, role: "reference")
        let target = try stableFace(targetFace, role: "target")

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommit = false
        defer {
            if didCommit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        // A Wrap reads its faces as the model is before it, so a replaced body that holds a picked
        // face is deformed after every other body; two such bodies cannot both come last.
        let faceHolders = Set([referenceFace.sceneNodeID, targetFace.sceneNodeID]).intersection(targets)
        if !options.keepsTools && targets.count > 1 && faceHolders.count > 1 {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot replace two bodies that hold the picked faces together; turn on Keep Tools or deform them apart."
            )
        }
        let ordered = targets.filter { !faceHolders.contains($0) } + targets.filter(faceHolders.contains)
        // Every placement is read before any body's object changes.
        struct Planned {
            var nodeID: SceneNodeID
            var name: String
            var wrap: WrapFeature
        }
        let planned = try ordered.map { nodeID -> Planned in
            guard let node = productMetadata.sceneNodes[nodeID], node.reference?.kind == .body,
                  let featureID = node.reference?.featureID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) deforms body objects; realize an instance before deforming it."
                )
            }
            guard !node.isLocked else {
                throw EditorError(code: .commandInvalid, message: "\(owner) cannot deform a locked object.")
            }
            _ = try bodyOrSheetPort(of: featureID, owner: owner)
            return Planned(nodeID: nodeID, name: node.name, wrap: WrapFeature(
                target: PatternTargetReference(featureID: featureID),
                referenceFace: reference,
                targetFace: target,
                referencePlacement: try relativeRigidPlacement(
                    of: referenceFace.sceneNodeID, inFrameOf: nodeID, owner: "The reference face", relation: "each body"
                ),
                targetPlacement: try relativeRigidPlacement(
                    of: targetFace.sceneNodeID, inFrameOf: nodeID, owner: "The target face", relation: "each body"
                ),
                options: wrapOptions,
                keepsTarget: options.keepsTools
            ))
        }
        var wraps: [FeatureID] = []
        for body in planned {
            let featureID = FeatureID()
            let name = "\(body.name) Deformed"
            try appendFeature(try FeatureNodeFactory.make(
                operation: .wrap(body.wrap), id: featureID, name: name, in: cadDocument, tolerance: modelingSettings.tolerance
            ))
            let geometryRole: ObjectDescriptor.GeometryRole =
                try bodyOrSheetPort(of: featureID, owner: owner) == .sheet ? .surface : .solid
            if options.keepsTools {
                try insertBooleanResultNode(
                    name: name, featureID: featureID, geometryRole: geometryRole, besideTargetNode: body.nodeID,
                    hierarchy: try SceneNodeHierarchy(metadata: productMetadata), objectRegistry: objectRegistry
                )
            } else {
                try retargetBodyNode(body.nodeID, to: featureID, name: name, geometryRole: geometryRole)
                try removeSceneNodes(presenting: [body.wrap.target.featureID])
            }
            wraps.append(featureID)
        }
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return wraps
    }
}
