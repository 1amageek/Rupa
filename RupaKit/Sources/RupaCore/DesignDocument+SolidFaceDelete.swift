import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func deleteBodyFaces(
        targets: [SelectionTarget],
        name: String = "Delete Face",
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operationName = "Delete Face"
        let trimmedName = try normalizedMetadataName(name, owner: operationName)
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
        var targetFeatureID: FeatureID?
        var targetSceneNodeID: SceneNodeID?
        var faceReferences: [StableSubshapeReference] = []
        var seenReferences: Set<StableSubshapeReference> = []

        for target in targets {
            guard case .face(let componentID) = target.component else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires generated topology face targets."
                )
            }
            let stableReference = try componentID.stableTopologyReference(
                operationName: operationName
            )
            guard seenReferences.insert(stableReference).inserted else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) face targets must be unique."
                )
            }

            let resolvedTarget = try editableBodyTargetResolution(
                for: target,
                operationName: operationName
            )
            if let existingFeatureID = targetFeatureID {
                guard existingFeatureID == resolvedTarget.featureID else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(operationName) currently requires all faces to belong to one body feature."
                    )
                }
            } else {
                targetFeatureID = resolvedTarget.featureID
                targetSceneNodeID = resolvedTarget.sceneNodeID
            }
            if let existingSceneNodeID = targetSceneNodeID {
                guard existingSceneNodeID == resolvedTarget.sceneNodeID else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(operationName) currently requires all faces to belong to one scene body."
                    )
                }
            }

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
            faceReferences.append(stableReference)
        }

        guard let targetFeatureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) could not resolve a target body feature."
            )
        }
        guard let targetFeature = cadDocument.designGraph.nodes[targetFeatureID],
              targetFeature.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a body-producing target feature."
            )
        }

        let faceDelete = FaceDeleteFeature(
            target: FaceDeleteTargetReference(featureID: targetFeatureID),
            faces: faceReferences
        )
        try faceDelete.validate()

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .faceDelete(faceDelete),
            inputs: [FeatureInput(featureID: targetFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .sheet)]
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
                geometryRole: .surface,
                properties: ObjectPropertySet(),
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommit = true
        return featureID
    }
}
