import RupaCore
import RupaViewportScene
import SwiftCAD

/// Immutable preparation inputs; camera revisions never rebuild these assets.
struct RealityViewportPreparationRequest: Sendable {
    struct Identity: Equatable, Sendable {
        let scene: ViewportSceneSnapshotKey
        let snapshotID: EvaluationSnapshotID?
        let overlayRevision: UInt64
    }

    let identity: Identity
    let scene: UniversalViewportScene?
    let fallbackOrigin: Point3D
    let spatialOverlay: @Sendable (Point3D, Int) throws -> ViewportSpatialOverlayProducer.Output
}
