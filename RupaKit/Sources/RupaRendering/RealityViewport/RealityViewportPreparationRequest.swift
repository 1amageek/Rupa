import RupaCore
import RupaViewportScene
import SwiftCAD

/// Immutable preparation inputs; camera revisions never rebuild these assets.
struct RealityViewportPreparationRequest: Sendable {
    struct Identity: Equatable, Sendable {
        let scene: ViewportSceneSnapshotKey
        let snapshotID: EvaluationSnapshotID?
        let overlayRevision: UInt64

        /// Scheduling/display compatibility only; never grants query authority.
        func sharesDisplayContext(with other: Self) -> Bool {
            guard snapshotID?.projectID == other.snapshotID?.projectID,
                  snapshotID?.purpose == other.snapshotID?.purpose else { return false }
            switch (scene.source, other.scene.source) {
            case let (.document(id, _), .document(otherID, _)):
                return id == otherID
            case let (.presentation(snapshot), .presentation(otherSnapshot)):
                return snapshot.projectID == otherSnapshot.projectID
                    && snapshot.purpose == otherSnapshot.purpose
            case let (.dragPreview(documentID, _), .dragPreview(otherID, _)):
                return documentID == otherID
            default:
                return false
            }
        }
    }

    let identity: Identity
    let scene: UniversalViewportScene?
    let fallbackOrigin: Point3D
    let spatialOverlay: @Sendable (Point3D, Int) throws -> ViewportSpatialOverlayProducer.Output
}
