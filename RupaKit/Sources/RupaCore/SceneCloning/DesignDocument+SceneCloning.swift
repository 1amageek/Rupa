import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// A self-contained copy of `ids` in world placement, for transport to this or another document.
    public func sceneFragment(copying ids: [SceneNodeID]) throws -> SceneFragment {
        try SceneFragmentExtractor().extract(
            rootSceneNodeIDs: ids,
            frame: .world,
            metadata: productMetadata,
            cadDocument: cadDocument
        )
    }

    /// Copies `ids` in place, as siblings right after them, and returns the copied roots.
    @discardableResult
    public mutating func duplicateSceneNodes(
        ids: [SceneNodeID],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        try placeSceneNodes(ids: ids, placements: [.identity], objectRegistry: objectRegistry)
    }

    /// Inserts one independent copy of `ids` per placement, each placement being a world-space
    /// transform applied to the selection, beside the selection, and returns the copied roots.
    @discardableResult
    public mutating func placeSceneNodes(
        ids: [SceneNodeID],
        placements: [Transform3D],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        let fragment = try sceneFragment(copying: ids)
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        let firstRootID = fragment.roots[0].sceneNodeID
        let rootIDs = Set(fragment.roots.map(\.sceneNodeID))
        let destination: SceneFragmentInserter.Attachment
        let parentWorld: Transform3D
        if let parentID = hierarchy.parentID(of: firstRootID), let parent = productMetadata.sceneNodes[parentID] {
            let lastIndex = parent.childIDs.lastIndex { rootIDs.contains($0) } ?? (parent.childIDs.count - 1)
            destination = .child(of: parentID, at: lastIndex + 1)
            parentWorld = try hierarchy.worldTransform(of: parentID)
        } else {
            destination = .documentRoot
            parentWorld = .identity
        }
        return try insertCopies(
            of: fragment,
            placements: placements,
            destination: destination,
            parentWorld: parentWorld,
            objectRegistry: objectRegistry
        )
    }

    /// Inserts one copy of `fragment` per world-space placement under the first document root and
    /// returns the copied roots.
    @discardableResult
    public mutating func pasteSceneFragment(
        _ fragment: SceneFragment,
        placements: [Transform3D],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SceneNodeID] {
        let destination: SceneFragmentInserter.Attachment
        let parentWorld: Transform3D
        if let rootID = productMetadata.rootSceneNodeIDs.first, let root = productMetadata.sceneNodes[rootID] {
            destination = .child(of: rootID, at: root.childIDs.count)
            parentWorld = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: rootID)
        } else {
            destination = .documentRoot
            parentWorld = .identity
        }
        return try insertCopies(
            of: fragment,
            placements: placements,
            destination: destination,
            parentWorld: parentWorld,
            objectRegistry: objectRegistry
        )
    }

    private mutating func insertCopies(
        of fragment: SceneFragment,
        placements: [Transform3D],
        destination: SceneFragmentInserter.Attachment,
        parentWorld: Transform3D,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [SceneNodeID] {
        guard !placements.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Placing copies requires at least one placement.")
        }
        var metadata = productMetadata
        var document = cadDocument
        var copiedRootIDs: [SceneNodeID] = []
        var nextDestination = destination
        for placement in placements {
            try placement.validateAffinePlacement()
            let insertion = try SceneFragmentInserter().insert(
                fragment,
                placement: placement,
                parentWorld: parentWorld,
                attachment: nextDestination,
                naming: .copy,
                metadata: &metadata,
                cadDocument: &document
            )
            copiedRootIDs.append(contentsOf: insertion.rootSceneNodeIDs)
            // Later copies follow earlier ones among the same siblings.
            if case .child(let parentID, let index) = nextDestination {
                nextDestination = .child(of: parentID, at: index + insertion.rootSceneNodeIDs.count)
            }
        }
        try document.validate(tolerance: .standard)
        try metadata.validate(against: document, objectRegistry: objectRegistry)
        cadDocument = document
        productMetadata = metadata
        return copiedRootIDs
    }
}
