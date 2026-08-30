import RupaCoreTypes

public struct SceneGraphSnapshotResult: Codable, Equatable, Sendable {
    public var generation: DocumentGeneration
    public var dirty: Bool
    public var rootSceneNodeIDs: [SceneNodeID]
    public var nodes: [SceneGraphNodeSnapshot]

    public init(
        generation: DocumentGeneration,
        dirty: Bool,
        rootSceneNodeIDs: [SceneNodeID],
        nodes: [SceneGraphNodeSnapshot]
    ) {
        self.generation = generation
        self.dirty = dirty
        self.rootSceneNodeIDs = rootSceneNodeIDs
        self.nodes = nodes
    }
}
