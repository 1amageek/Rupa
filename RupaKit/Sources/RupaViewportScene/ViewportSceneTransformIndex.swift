import RupaCore

package struct ViewportSceneTransformIndex {
    private let hierarchy: SceneNodeHierarchy

    package init(metadata: ProductMetadata) throws {
        self.hierarchy = try SceneNodeHierarchy(metadata: metadata)
    }

    package func resolvedOccurrences() throws -> [SceneNodeHierarchy.Occurrence] {
        try hierarchy.resolvedOccurrences()
    }

    package var orderedSceneNodeIDs: [SceneNodeID] {
        hierarchy.orderedSceneNodeIDs
    }

    package func node(_ sceneNodeID: SceneNodeID) -> SceneNode? {
        hierarchy.node(sceneNodeID)
    }

    package func ancestorIDs(of sceneNodeID: SceneNodeID) -> [SceneNodeID] {
        hierarchy.ancestorIDs(of: sceneNodeID)
    }

    package func presentingSceneNodeID(for featureID: FeatureID) -> SceneNodeID? {
        hierarchy.presentingSceneNodeID(for: featureID)
    }

    package func transform(for sceneNodeID: SceneNodeID) throws -> Transform3D {
        try hierarchy.worldTransform(of: sceneNodeID)
    }
}
