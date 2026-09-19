import RupaCore

/// What the placement actions may do with the current selection.
///
/// The commands themselves rebuild the scene tree and reject anything they cannot carry out, so
/// this state exists only to keep the controls honest: a button that is offered has to work. It is
/// derived from the selection alone, which keeps it cheap enough to read while the browser draws.
struct WorkspaceSelectionPlacementActionState: Equatable, Sendable {
    /// Selected nodes that may be re-parented, moved, or turned.
    var placeableIDs: [SceneNodeID]
    /// Selected nodes that carry no geometry of their own and can therefore be dissolved.
    var dissolvableGroupIDs: [SceneNodeID]
    /// Whether the selection reaches a scene root, which owns the coordinate system the rest of
    /// the tree is placed in and so cannot itself be placed.
    var includesSceneRoot: Bool

    init(
        placeableIDs: [SceneNodeID] = [],
        dissolvableGroupIDs: [SceneNodeID] = [],
        includesSceneRoot: Bool = false
    ) {
        self.placeableIDs = placeableIDs
        self.dissolvableGroupIDs = dissolvableGroupIDs
        self.includesSceneRoot = includesSceneRoot
    }

    init(metadata: ProductMetadata, selectedSceneNodeIDs: [SceneNodeID]) {
        let rootIDs = Set(metadata.rootSceneNodeIDs)
        var placeableIDs: [SceneNodeID] = []
        var dissolvableGroupIDs: [SceneNodeID] = []
        var includesSceneRoot = false

        for id in selectedSceneNodeIDs {
            guard let node = metadata.sceneNodes[id] else {
                continue
            }
            guard !rootIDs.contains(id) else {
                includesSceneRoot = true
                continue
            }
            placeableIDs.append(id)
            if node.isGroupingNode {
                dissolvableGroupIDs.append(id)
            }
        }

        self.init(
            placeableIDs: placeableIDs,
            dissolvableGroupIDs: dissolvableGroupIDs,
            includesSceneRoot: includesSceneRoot
        )
    }

    var canGroup: Bool {
        !includesSceneRoot && !placeableIDs.isEmpty
    }

    var canUngroup: Bool {
        !dissolvableGroupIDs.isEmpty
    }
}
