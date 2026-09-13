import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// The mounted frame, answering the three affordance drag queries.
///
/// The preparation identity and control revision are captured once, by the
/// caller that already validated them for this update, so both ends of a
/// two-point sample resolve against one camera and a camera move during the
/// drag cannot mix two projections into one displacement.
@MainActor
struct ViewportNativeAffordanceMeasure: ViewportAffordanceMeasuring {
    let planCache: MeshSourcePresentationPlanCache
    let identity: RealityViewportPreparationRequest.Identity
    let revision: UInt64

    func worldAxisDelta(
        from start: CGPoint,
        to end: CGPoint,
        axisOrigin: Point3D,
        axisDirection: Vector3D
    ) throws -> Double {
        try planCache.worldAxisDelta(
            from: start,
            to: end,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            for: identity,
            revision: revision
        )
    }

    func worldPlanePoint(
        at point: CGPoint,
        planeOrigin: Point3D,
        planeNormal: Vector3D
    ) throws -> Point3D {
        try planCache.worldPlaneIntersection(
            at: point,
            planeOrigin: planeOrigin,
            planeNormal: planeNormal,
            for: identity,
            revision: revision
        )
    }

    func viewPlanePoint(at point: CGPoint, through anchor: Point3D) throws -> Point3D {
        try planCache.viewPlaneIntersection(
            at: point,
            through: anchor,
            for: identity,
            revision: revision
        )
    }
}
