import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func draftBodyFaces(
        targets: [SelectionTarget],
        neutralTarget: SelectionTarget,
        angle: CADExpression,
        name: String = "Draft Face",
        objectRegistry: ObjectTypeRegistry = .builtIn
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

        let topology = try TopologySnapshotService().snapshot(
            document: self,
            objectRegistry: objectRegistry
        )
        let entriesByStableReference = Dictionary(
            uniqueKeysWithValues: topology.entries.map { ($0.stableReference, $0) }
        )
        let targetResolutions = try targets.map { target in
            try generatedFaceDraftTarget(
                target,
                entriesByStableReference: entriesByStableReference,
                operationName: operationName
            )
        }
        let neutralResolution = try generatedFaceDraftTarget(
            neutralTarget,
            entriesByStableReference: entriesByStableReference,
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
        let targetReferences = targetResolutions.map(\.stableReference)
        guard Set(targetReferences).count == targetReferences.count else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target faces must be distinct."
            )
        }
        guard targetReferences.contains(neutralResolution.stableReference) == false else {
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

        let faceDraft = FaceDraftFeature(
            target: FaceDraftTargetReference(featureID: neutralResolution.featureID),
            faces: targetReferences,
            neutralFace: neutralResolution.stableReference,
            angle: angle
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

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: nil,
                geometryRole: .solid,
                properties: ObjectPropertySet(),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }

    private struct FaceDraftTargetResolution {
        var sceneNodeID: SceneNodeID
        var featureID: FeatureID
        var stableReference: StableSubshapeReference
    }

    private func generatedFaceDraftTarget(
        _ target: SelectionTarget,
        entriesByStableReference: [StableSubshapeReference: TopologySummaryResult.Entry],
        operationName: String
    ) throws -> FaceDraftTargetResolution {
        guard case .face(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires generated topology face targets."
            )
        }
        let stableReference = try componentID.stableTopologyReference(
            operationName: operationName
        )
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: operationName
        )
        guard let entry = entriesByStableReference[stableReference] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated topology face was not found in the current evaluation."
            )
        }
        guard entry.kind == .face,
              entry.sceneNodeID == resolvedTarget.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) targets must reference faces on the selected body."
            )
        }
        return FaceDraftTargetResolution(
            sceneNodeID: resolvedTarget.sceneNodeID,
            featureID: resolvedTarget.featureID,
            stableReference: stableReference
        )
    }
}
