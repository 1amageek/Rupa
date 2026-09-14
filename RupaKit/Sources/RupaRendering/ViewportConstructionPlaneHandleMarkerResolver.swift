import CoreGraphics
import RupaCore

/// Places the construction-plane accessibility markers on the mounted frame.
///
/// The markers name the same handles the native overlay draws, so they read
/// the prepared interaction records of the frame that drew them and project
/// each record's own point through that frame. The record's placement is left
/// unapplied because the drawn handle and the world-point drag route both use
/// those points directly.
@MainActor
struct ViewportConstructionPlaneHandleMarkerResolver {
    /// The markers for the frame prepared under `identity` at `revision`.
    ///
    /// An empty result means the frame draws no construction-plane handle, or
    /// that it is not ready to answer yet; readiness is decided before any
    /// projection is attempted so a cold mount is never reported as a failure.
    /// Past that gate every failure is thrown for the surface seam to report.
    static func resolve(
        planCache: MeshSourcePresentationPlanCache,
        identity: RealityViewportPreparationRequest.Identity,
        revision: UInt64
    ) throws -> [ViewportConstructionPlaneHandleMarker] {
        guard planCache.hasReadyCamera(for: identity, revision: revision) else { return [] }
        let probe = try ViewportNativePresentationFrameProbe(
            planCache: planCache,
            identity: identity,
            revision: revision
        )
        var markers: [ViewportConstructionPlaneHandleMarker] = []
        for record in try planCache.interactionRecords(for: identity) {
            guard case let .constructionPlane(
                handleIdentity, origin, normal, normalEnd, _
            ) = record.target else { continue }
            let anchor: Point3D = switch handleIdentity.handle {
            case .origin: origin
            case .normal: normalEnd
            }
            guard let projected = try probe.projectedPointWithinDepthRange(anchor) else { continue }
            markers.append(
                ViewportConstructionPlaneHandleMarker(
                    identity: handleIdentity,
                    point: projected.point,
                    origin: origin,
                    normal: normal
                )
            )
        }
        return markers
    }
}
