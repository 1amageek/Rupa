import Foundation
import SwiftCAD
import RupaCoreTypes

/// Removing objects from the document.
///
/// A delete is the one edit whose reach the user cannot see before committing to it, so it is applied
/// to a copy and only adopted once the whole document validates. A partially applied delete would
/// leave the scene naming features that no longer exist, which no later command could repair.
extension DesignDocument {
    /// Deletes `ids` together with everything that cannot outlive them, and returns the plan applied.
    ///
    /// The returned plan is what lets the caller say the delete reached further than the selection,
    /// which the browser cannot show once the rows are gone.
    @discardableResult
    public mutating func deleteSceneNodes(
        ids: [SceneNodeID],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SceneNodeDeletionPlan {
        let plan = try SceneNodeDeletionPlanner().plan(
            metadata: productMetadata,
            designGraph: cadDocument.designGraph,
            ids: ids
        )

        var updatedDocument = self
        // Features first: the kernel refuses to remove one that still has dependents, and the plan's
        // order is the graph's build order read backwards, which is exactly that guarantee.
        for featureID in plan.featureIDs {
            updatedDocument.cadDocument = try DocumentEditor().apply(
                .removeFeature(featureID),
                to: updatedDocument.cadDocument,
                tolerance: modelingSettings.tolerance
            )
        }
        // Scene nodes deepest first, so each one is childless when it is removed.
        for sceneNodeID in plan.sceneNodeIDs {
            try updatedDocument.productMetadata.removeSceneNode(sceneNodeID)
        }
        for componentInstanceID in plan.componentInstanceIDs {
            updatedDocument.productMetadata.componentInstances[componentInstanceID] = nil
        }
        for constructionPlaneID in plan.constructionPlaneIDs {
            updatedDocument.productMetadata.constructionPlanes[constructionPlaneID] = nil
        }
        for bindingID in plan.topologyMaterialBindingIDs {
            updatedDocument.productMetadata.topologyMaterialBindings[bindingID] = nil
        }
        for measurementID in plan.measurementIDs {
            updatedDocument.productMetadata.measurements[measurementID] = nil
        }
        for sourceID in plan.bridgeCurveSourceIDs {
            updatedDocument.productMetadata.bridgeCurveSources[sourceID] = nil
        }
        for sourceID in plan.joinedCurveSourceIDs {
            updatedDocument.productMetadata.joinedCurveSources[sourceID] = nil
        }
        for sourceID in plan.joinedCurveGroupSourceIDs {
            updatedDocument.productMetadata.joinedCurveGroupSources[sourceID] = nil
        }

        try updatedDocument.validate(objectRegistry: objectRegistry)
        self = updatedDocument
        return plan
    }
}
