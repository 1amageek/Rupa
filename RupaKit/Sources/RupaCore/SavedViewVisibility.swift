public struct SavedViewVisibility: Codable, Hashable, Sendable {
    public var visibleSceneNodeIDs: [SceneNodeID]
    public var hiddenSceneNodeIDs: [SceneNodeID]

    public init(
        visibleSceneNodeIDs: [SceneNodeID] = [],
        hiddenSceneNodeIDs: [SceneNodeID] = []
    ) {
        self.visibleSceneNodeIDs = visibleSceneNodeIDs
        self.hiddenSceneNodeIDs = hiddenSceneNodeIDs
    }

    public func validate(sceneNodes: [SceneNodeID: SceneNode]) throws {
        guard Set(visibleSceneNodeIDs).count == visibleSceneNodeIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view visible scene node references must be unique."
            )
        }
        guard Set(hiddenSceneNodeIDs).count == hiddenSceneNodeIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view hidden scene node references must be unique."
            )
        }
        let visibleIDs = Set(visibleSceneNodeIDs)
        let hiddenIDs = Set(hiddenSceneNodeIDs)
        guard visibleIDs.isDisjoint(with: hiddenIDs) else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view scene node references cannot be both visible and hidden."
            )
        }
        for sceneNodeID in visibleIDs.union(hiddenIDs) {
            guard sceneNodes[sceneNodeID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view visibility references a missing scene node."
                )
            }
        }
    }
}
