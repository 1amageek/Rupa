import RupaCore

/// Bridge Edge's dialog while it runs, on the two body edges selected when L started it: Side 1
/// and Side 2 choose which end of each edge the bridge leaves from (seeded with their nearest
/// ends), each end takes G0 to G3 and a tension, and OK, Return or right-click makes the bridge;
/// Escape ends it without a change.
struct WorkspaceBridgeEdgeSession: Equatable {
    /// This dialog, apart from the one the command starts next (`WorkspaceDialogSubmissions`).
    let instance = WorkspaceDialogInstance()

    let first: SelectionTarget
    let second: SelectionTarget
    /// Side 1 and Side 2: the edge's end (true) or start (false).
    var firstAtEnd: Bool
    var secondAtEnd: Bool
    var continuity: BridgeCurveContinuity
    var tensions: SpatialBridgeTensions

    init(nearest: (SpatialBridgeEnd, SpatialBridgeEnd)) {
        first = nearest.0.target
        second = nearest.1.target
        firstAtEnd = nearest.0.fraction >= 0.5
        secondAtEnd = nearest.1.fraction >= 0.5
        continuity = .g1
        tensions = SpatialBridgeTensions()
    }

    var command: EditorCommand {
        .createBridgeCurveBetweenEnds(
            first: SpatialBridgeEnd(target: first, fraction: firstAtEnd ? 1 : 0),
            second: SpatialBridgeEnd(target: second, fraction: secondAtEnd ? 1 : 0),
            continuity: continuity,
            tensions: tensions
        )
    }
}
