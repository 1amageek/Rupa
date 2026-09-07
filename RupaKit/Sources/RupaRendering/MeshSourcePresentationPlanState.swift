import RupaCoreTypes

/// The lifecycle of one asynchronously prepared presentation render plan.
///
/// The state is keyed by the `EvaluationSnapshotID` of the scene it describes,
/// so a consumer can only read a plan or a failure that belongs to the scene it
/// is currently rendering. A completion whose identity no longer matches is
/// discarded rather than published, which is what makes a superseded build
/// unable to overwrite a newer one.
enum MeshSourcePresentationPlanState {
    /// No scene has been prepared, or the owning viewport has torn down.
    case idle
    /// A build for `snapshotID` is in flight. Nothing is exposed to rendering
    /// or picking while a scene is in this state.
    case preparing(snapshotID: EvaluationSnapshotID)
    /// The build for `snapshotID` completed and its plan is the only plan the
    /// cache exposes.
    case ready(snapshotID: EvaluationSnapshotID, plan: MeshSourcePresentationRenderPlan, surface: RealityViewport)
    /// The build for `snapshotID` failed. The failure is exposed so it can be
    /// distinguished on screen from a scene that is still preparing.
    case failed(snapshotID: EvaluationSnapshotID, error: MeshSourcePresentationRenderError)

    /// The scene identity this state describes, or `nil` when idle.
    var snapshotID: EvaluationSnapshotID? {
        switch self {
        case .idle:
            return nil
        case let .preparing(snapshotID):
            return snapshotID
        case let .ready(snapshotID, _, _):
            return snapshotID
        case let .failed(snapshotID, _):
            return snapshotID
        }
    }
}
