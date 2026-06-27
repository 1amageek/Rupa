import RupaCore

package struct ViewportSceneTransformIndex {
    private var transformsBySceneNodeID: [SceneNodeID: Transform3D]

    package init(metadata: ProductMetadata) {
        var transformsBySceneNodeID: [SceneNodeID: Transform3D] = [:]
        var visitedIDs: Set<SceneNodeID> = []
        for rootSceneNodeID in metadata.rootSceneNodeIDs {
            Self.appendTransforms(
                rootSceneNodeID,
                parentTransform: .identity,
                metadata: metadata,
                transformsBySceneNodeID: &transformsBySceneNodeID,
                visitedIDs: &visitedIDs
            )
        }
        self.transformsBySceneNodeID = transformsBySceneNodeID
    }

    package func transform(for sceneNodeID: SceneNodeID) -> Transform3D {
        transformsBySceneNodeID[sceneNodeID] ?? .identity
    }

    private static func appendTransforms(
        _ sceneNodeID: SceneNodeID,
        parentTransform: Transform3D,
        metadata: ProductMetadata,
        transformsBySceneNodeID: inout [SceneNodeID: Transform3D],
        visitedIDs: inout Set<SceneNodeID>
    ) {
        guard visitedIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        let transform = parentTransform.concatenating(sceneNode.localTransform)
        transformsBySceneNodeID[sceneNodeID] = transform
        for childID in sceneNode.childIDs {
            appendTransforms(
                childID,
                parentTransform: transform,
                metadata: metadata,
                transformsBySceneNodeID: &transformsBySceneNodeID,
                visitedIDs: &visitedIDs
            )
        }
    }
}
