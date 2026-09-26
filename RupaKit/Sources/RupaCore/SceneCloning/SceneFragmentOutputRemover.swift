import SwiftCAD

/// Removes inserted copies: their scene subtrees, their features and every side-table entry keyed
/// by either, so no binding or edit source is left naming something that no longer exists.
struct SceneFragmentOutputRemover: Sendable {
    func remove(
        rootedAt rootSceneNodeIDs: [SceneNodeID],
        featureIDs: Set<FeatureID>,
        metadata: inout ProductMetadata,
        cadDocument: inout CADDocument
    ) {
        var removedSceneNodeIDs: Set<SceneNodeID> = []
        var pending = rootSceneNodeIDs
        while let id = pending.popLast() {
            guard removedSceneNodeIDs.insert(id).inserted,
                  let node = metadata.sceneNodes[id] else {
                continue
            }
            pending.append(contentsOf: node.childIDs)
        }
        if !removedSceneNodeIDs.isEmpty {
            for id in removedSceneNodeIDs {
                metadata.sceneNodes.removeValue(forKey: id)
            }
            metadata.rootSceneNodeIDs.removeAll { removedSceneNodeIDs.contains($0) }
            for id in metadata.sceneNodes.keys {
                metadata.sceneNodes[id]?.childIDs.removeAll { removedSceneNodeIDs.contains($0) }
            }
            metadata.topologyMaterialBindings = metadata.topologyMaterialBindings.filter {
                !removedSceneNodeIDs.contains($0.value.target.sceneNodeID)
            }
        }
        guard !featureIDs.isEmpty else {
            return
        }
        metadata.bridgeCurveSources = metadata.bridgeCurveSources.filter { !featureIDs.contains($0.value.featureID) }
        metadata.joinedCurveSources = metadata.joinedCurveSources.filter { !featureIDs.contains($0.value.featureID) }
        metadata.joinedCurveGroupSources = metadata.joinedCurveGroupSources.filter {
            !featureIDs.contains($0.value.featureID)
        }
        cadDocument.designGraph.order.removeAll { featureIDs.contains($0) }
        for featureID in featureIDs {
            cadDocument.designGraph.nodes.removeValue(forKey: featureID)
        }
        cadDocument.designGraph.dependencies.removeAll {
            featureIDs.contains($0.source) || featureIDs.contains($0.target)
        }
        cadDocument.designGraph.revision = cadDocument.designGraph.revision.advanced()
    }
}
