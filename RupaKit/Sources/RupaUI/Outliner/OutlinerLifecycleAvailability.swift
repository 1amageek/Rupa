import RupaCore

/// What Group, Ungroup, and Delete may do with a set of rows.
///
/// Each of the three becomes one Core command that refuses a whole selection rather than trimming
/// it, so a control that is offered has to have asked for the same refusals first. Availability and
/// the intent that is sent read the same value here, so what the menu offers and what the tree sends
/// cannot drift apart. It is derived from immutable metadata and the current projection, which keeps
/// it cheap enough to read while a menu lays out.
struct OutlinerLifecycleAvailability: Equatable, Sendable {
    /// The members Group would collect, empty when Group is unavailable.
    let groupableIDs: [SceneNodeID]
    /// The groups Ungroup would dissolve, empty when Ungroup is unavailable.
    let dissolvableIDs: [SceneNodeID]
    /// The rows Delete would remove, empty when Delete is unavailable.
    let deletableIDs: [SceneNodeID]

    init(
        ids: [SceneNodeID],
        metadata: ProductMetadata,
        projection: OutlinerProjection
    ) {
        let placement = WorkspaceSelectionPlacementActionState(
            metadata: metadata,
            selectedSceneNodeIDs: ids
        )
        // Grouping and ungrouping both re-parent, so they ask of a row exactly what a drag asks.
        groupableIDs = placement.canGroup && projection.canMove(ids: placement.placeableIDs)
            ? placement.placeableIDs
            : []
        dissolvableIDs = placement.canUngroup
            && projection.canMove(ids: placement.dissolvableGroupIDs)
            ? placement.dissolvableGroupIDs
            : []
        deletableIDs = Self.deletableIDs(among: ids, metadata: metadata, projection: projection)
    }

    var canGroup: Bool {
        !groupableIDs.isEmpty
    }

    var canUngroup: Bool {
        !dissolvableIDs.isEmpty
    }

    var canDelete: Bool {
        !deletableIDs.isEmpty
    }

    /// The Group control's title. An unavailable Group keeps the bare verb, because a disabled
    /// control still has to read as the action it names rather than as a count of nothing.
    var groupActionTitle: String {
        switch groupableIDs.count {
        case 0: return "Group"
        case 1: return "Group Object"
        default: return "Group \(groupableIDs.count) Objects"
        }
    }

    var ungroupActionTitle: String {
        dissolvableIDs.count > 1 ? "Ungroup \(dissolvableIDs.count) Groups" : "Ungroup"
    }

    /// Core refuses a delete that reaches a root, a locked node, or generated pattern output rather
    /// than trimming it, so a selection that is only partly deletable offers no delete at all.
    private static func deletableIDs(
        among ids: [SceneNodeID],
        metadata: ProductMetadata,
        projection: OutlinerProjection
    ) -> [SceneNodeID] {
        guard projection.canMutate(ids: ids) else {
            return []
        }
        let rootIDs = Set(metadata.rootSceneNodeIDs)
        let isDeletable = ids.allSatisfy { id in
            guard let row = projection.row(for: id) else {
                return false
            }
            return !row.isLocked && !rootIDs.contains(id)
        }
        return isDeletable ? ids : []
    }
}
