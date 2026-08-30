public struct SceneGraphSnapshotService: Sendable {
    public init() {}

    public func result(
        document: DesignDocument,
        generation: DocumentGeneration,
        dirty: Bool
    ) -> SceneGraphSnapshotResult {
        let metadata = document.productMetadata
        let nodes = metadata.sceneNodes.values
            .sorted { $0.id < $1.id }
            .map { node in
                SceneGraphNodeSnapshot(
                    id: node.id,
                    name: node.name,
                    reference: node.reference,
                    objectCategory: node.object?.category,
                    geometryRole: node.object?.geometryRole,
                    sourceFeatureID: node.object?.sourceFeatureID,
                    childIDs: node.childIDs,
                    isVisible: node.isVisible,
                    isLocked: node.isLocked,
                    localTransform: node.localTransform,
                    materialID: node.materialID
                )
            }
        return SceneGraphSnapshotResult(
            generation: generation,
            dirty: dirty,
            rootSceneNodeIDs: metadata.rootSceneNodeIDs,
            nodes: nodes
        )
    }
}
