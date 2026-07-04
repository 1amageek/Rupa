public struct SavedViewSectionState: Codable, Hashable, Sendable {
    public var activeConstructionPlaneID: ConstructionPlaneSourceID?
    public var sectionSceneNodeIDs: [SceneNodeID]

    public init(
        activeConstructionPlaneID: ConstructionPlaneSourceID? = nil,
        sectionSceneNodeIDs: [SceneNodeID] = []
    ) {
        self.activeConstructionPlaneID = activeConstructionPlaneID
        self.sectionSceneNodeIDs = sectionSceneNodeIDs
    }

    public func validate(
        sceneNodes: [SceneNodeID: SceneNode],
        constructionPlanes: [ConstructionPlaneSourceID: ConstructionPlaneSource]
    ) throws {
        if let activeConstructionPlaneID,
           constructionPlanes[activeConstructionPlaneID] == nil {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view active construction plane references a missing construction plane."
            )
        }
        guard Set(sectionSceneNodeIDs).count == sectionSceneNodeIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Saved view section scene node references must be unique."
            )
        }
        for sceneNodeID in sectionSceneNodeIDs {
            guard let sceneNode = sceneNodes[sceneNodeID] else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view section state references a missing scene node."
                )
            }
            guard sceneNode.reference?.kind == .construction else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Saved view section state must reference construction scene nodes."
                )
            }
        }
    }
}
