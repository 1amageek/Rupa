import CoreGraphics
import RupaCore
import RupaViewportScene

/// Answers the view-ray anchor a canvas gesture carries from the mounted frame.
///
/// The anchor is the ray origin the workspace canvas mapper casts along the
/// view normal when the gesture names no exact world point, so substituting a
/// different origin moves the geometry the gesture creates. The anchor is
/// therefore taken from the same authority the rest of the gesture uses -- the
/// mounted frame's world-plane intersection under the identity and camera
/// revision the canvas input itself used -- and a canvas plane that names no
/// normal or a frame that cannot answer the intersection refuses instead of
/// yielding a point from another ray origin.
@MainActor
struct ViewportCanvasViewRayAnchorResolver {
    enum Failure: Error, Equatable {
        /// The displayed canvas plane names two collinear axes, so it spans no
        /// plane the frame could intersect.
        case undefinedCanvasPlaneNormal
    }

    static func resolve(
        at point: CGPoint,
        canvasPlane: ViewportCanvasPlane,
        planCache: MeshSourcePresentationPlanCache,
        identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> Point3D {
        guard let normal = canvasPlane.normal else {
            throw Failure.undefinedCanvasPlaneNormal
        }
        return try planCache.worldPlaneIntersection(
            at: point,
            planeOrigin: canvasPlane.worldPoint(first: 0, second: 0),
            planeNormal: normal,
            for: identity,
            revision: revision
        )
    }
}
