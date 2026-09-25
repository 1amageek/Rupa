import Foundation

/// The mapping from a feature to the one scene node that presents its evaluated geometry.
///
/// Only feature, body and sketch references present evaluated geometry. Product metadata
/// validation and ``SceneNodeHierarchy`` both build this index so the one-presenting-node rule is
/// defined once and reported through each owner's error type.
struct FeaturePresentationIndex: Sendable {
    struct Conflict: Sendable {
        var featureID: FeatureID
        var sceneNodeIDs: [SceneNodeID]

        var message: String {
            let ids = sceneNodeIDs.sorted().map(\.description).joined(separator: ", ")
            return "Feature \(featureID.description) is presented by more than one scene node (\(ids))."
        }
    }

    private(set) var sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID] = [:]
    private(set) var conflict: Conflict?

    init(sceneNodes: [SceneNodeID: SceneNode]) {
        var sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID] = [:]
        var conflictingIDsByFeatureID: [FeatureID: [SceneNodeID]] = [:]
        for (sceneNodeID, node) in sceneNodes {
            guard let featureID = node.reference?.featureID else {
                continue
            }
            if let existingID = sceneNodeIDsByFeatureID[featureID] {
                conflictingIDsByFeatureID[featureID, default: [existingID]].append(sceneNodeID)
            } else {
                sceneNodeIDsByFeatureID[featureID] = sceneNodeID
            }
        }
        self.sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID
        // Report the smallest conflicting feature ID so the message is stable across runs.
        if let featureID = conflictingIDsByFeatureID.keys.min(),
           let ids = conflictingIDsByFeatureID[featureID] {
            self.conflict = Conflict(featureID: featureID, sceneNodeIDs: ids)
        }
    }
}
