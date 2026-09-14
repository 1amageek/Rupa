import CoreGraphics
import RupaCore

/// Where the mounted frame drew one construction-plane handle.
///
/// The accessibility marker that reports the handle to the chrome is placed
/// from this value, so its screen point comes from the frame that drew the
/// handle rather than from a second projection of the document. The world
/// values are the ones the prepared record carries, because the reported
/// value describes the plane, not the marker.
struct ViewportConstructionPlaneHandleMarker: Equatable, Sendable {
    let identity: ViewportConstructionPlaneHandleIdentity
    let point: CGPoint
    let origin: Point3D
    let normal: Vector3D
}
