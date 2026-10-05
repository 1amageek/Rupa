import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Draft Face, isocline: the target faces turn about their crossing with the neutral face's
    /// plane, moved `neutralOffset` along its outward side, so each makes `angle` with the pull
    /// direction (its outward normal), a positive angle leaning them out away from the plane. A
    /// curved neutral face (no offset) turns each face about the straight edge it shares with it.
    @discardableResult
    public mutating func draftBodyFaces(
        targets: [SelectionTarget],
        neutralTarget: SelectionTarget,
        angle: CADExpression,
        neutralOffset: CADExpression? = nil,
        grow: FaceEditGrow = .moving,
        method: BodyFaceDraftMethod = .isocline,
        name: String = "Draft Face",
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> FeatureID {
        let operationName = "Draft Face"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
        let angleRadians = try resolvedAngleValue(angle, owner: "\(operationName) angle")
        guard abs(angleRadians) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) angle must not be zero."
            )
        }
        guard abs(angleRadians) < (Double.pi / 2.0) - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) angle must be smaller than 90 degrees."
            )
        }
        guard targets.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires at least one generated face target."
            )
        }
        if let neutralOffset {
            _ = try resolvedLengthValue(neutralOffset, owner: "\(operationName) neutral offset")
        }

        let topology = try TopologySnapshotService().snapshot(
            document: self,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let entriesBySubshapeID = Dictionary(
            uniqueKeysWithValues: topology.entries.map { ($0.subshapeID, $0) }
        )
        let targetResolutions = try targets.map { target in
            try generatedFaceDraftTarget(
                target,
                entriesBySubshapeID: entriesBySubshapeID,
                operationName: operationName
            )
        }
        let neutralResolution = try generatedFaceDraftTarget(
            neutralTarget,
            entriesBySubshapeID: entriesBySubshapeID,
            operationName: operationName
        )
        guard targetResolutions.allSatisfy({ $0.featureID == neutralResolution.featureID }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target and neutral faces must belong to one body feature."
            )
        }
        guard targetResolutions.allSatisfy({ $0.sceneNodeID == neutralResolution.sceneNodeID }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target and neutral faces must belong to one scene body."
            )
        }
        let targetFaces = targetResolutions.map(\.face)
        guard Set(targetFaces.map(\.subshapeID)).count == targetFaces.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target faces must be distinct."
            )
        }
        guard targetFaces.map(\.subshapeID).contains(neutralResolution.face.subshapeID) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target face and neutral face must be distinct."
            )
        }
        guard let targetFeature = cadDocument.designGraph.nodes[neutralResolution.featureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        // The method's picks lie on the drafted body: pivot edges for Curve, the pull's face for Surface.
        let kernelMethod: FaceDraftMethod
        switch method {
        case .isocline:
            kernelMethod = .isocline
        case .normal:
            kernelMethod = .normal
        case let .curve(pivots):
            guard pivots.isEmpty == false else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) Curve needs at least one pivot edge.")
            }
            kernelMethod = .curve(pivots: try pivots.map { pivot in
                let resolution = try generatedFaceDraftTarget(
                    pivot, kind: .edge, entriesBySubshapeID: entriesBySubshapeID, operationName: operationName
                )
                guard resolution.sceneNodeID == neutralResolution.sceneNodeID else {
                    throw EditorError(code: .commandInvalid, message: "\(operationName) pivot edges must belong to the drafted body.")
                }
                return resolution.face
            })
        case let .surface(reference):
            let resolution = try generatedFaceDraftTarget(
                reference, entriesBySubshapeID: entriesBySubshapeID, operationName: operationName
            )
            guard resolution.sceneNodeID == neutralResolution.sceneNodeID else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) Surface reference must be a face of the drafted body.")
            }
            kernelMethod = .surface(reference: resolution.face)
        }
        let faceDraft = FaceDraftFeature(
            target: FaceDraftTargetReference(featureID: neutralResolution.featureID),
            faces: targetFaces,
            neutralFace: neutralResolution.face,
            angle: angle,
            neutralOffset: neutralOffset,
            grow: grow,
            method: kernelMethod
        )
        try faceDraft.validate()

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .faceDraft(faceDraft),
            inputs: [FeatureInput(featureID: neutralResolution.featureID, role: .target)],
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

        try appendTopologyEdit(
            FeatureGraphTransaction(features: [feature], primaryFeatureID: featureID),
            replacing: SelectionTarget(sceneNodeID: neutralResolution.sceneNodeID),
            objectRegistry: objectRegistry
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    private struct FaceDraftTargetResolution {
        var sceneNodeID: SceneNodeID
        var featureID: FeatureID
        var face: StableSubshapeReference
    }

    private enum FaceDraftPickKind { case face, edge }

    private func generatedFaceDraftTarget(
        _ target: SelectionTarget,
        kind: FaceDraftPickKind = .face,
        entriesBySubshapeID: [String: TopologySummaryResult.Entry],
        operationName: String
    ) throws -> FaceDraftTargetResolution {
        let picked: SelectionComponentID?
        switch (kind, target.component) {
        case (.face, .face(let componentID)), (.edge, .edge(let componentID)): picked = componentID
        default: picked = nil
        }
        guard let componentID = picked, let subshapeID = componentID.generatedTopologySubshapeID else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated topology \(kind == .face ? "face" : "edge") targets."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        guard let entry = entriesBySubshapeID[GeneratedSubshapeIdentity.string(for: subshapeID)] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face was not found in the current evaluation."
            )
        }
        guard entry.kind == (kind == .face ? .face : .edge),
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) targets must reference faces on the selected body."
            )
        }
        guard let stableReference = entry.stableReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face has no stable subshape reference."
            )
        }
        return FaceDraftTargetResolution(
            sceneNodeID: resolvedTarget.sceneNodeID,
            featureID: resolvedTarget.featureID,
            face: stableReference
        )
    }
}
