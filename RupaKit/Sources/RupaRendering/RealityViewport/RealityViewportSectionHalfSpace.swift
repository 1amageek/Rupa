import simd

/// The kept side of one mounted frame's active section, in native scene space.
///
/// A section is a single half-space, and naming it makes the cut one
/// declaration instead of a tuple every reader unpacks. The frame's own
/// drawing decision, the query that reports the cut, the native collision
/// admission, the prepared line clip, and the region raster and probes all
/// read the scalar below, so none of them restates `dot - offset` or decides
/// on its own where the tolerance belongs.
///
/// Positions arrive `renderOrigin`-relative, because that is the space the
/// scene is built in and the space `offset` was derived in. Every caller
/// converts before asking, and this type never sees a CAD world coordinate.
///
/// `signedDistance(to:)` is affine in that space, which is what lets a probe
/// clip a segment against the cut in the segment's own parameter rather than
/// sample for it: the scalar is affine in the parameter, so the crossing is
/// exact. `ViewportCameraDepthClip` owns that clip. This type owns only the
/// scalar clipped against and the predicate that scalar decides.
struct RealityViewportSectionHalfSpace: Equatable, Sendable {
    /// Unit normal pointing into the kept side.
    let normal: SIMD3<Double>
    /// Distance from the native scene origin to the cut plane along `normal`.
    let offset: Double
    /// How far past the plane the kept side still admits. Never negative.
    let tolerance: Double

    init(normal: SIMD3<Double>, offset: Double, tolerance: Double) {
        self.normal = normal
        self.offset = offset
        self.tolerance = tolerance
    }

    /// The scalar the cut is decided on: positive into the kept side, zero on
    /// the plane itself. The kept side is `signedDistance(to:) >= -tolerance`,
    /// so `-tolerance` is the bound a segment clip narrows against.
    func signedDistance(to position: SIMD3<Double>) -> Double {
        simd_dot(position, normal) - offset
    }

    /// Whether the frame keeps `position`. This is the one admission
    /// predicate; no reader compares its own distance against its own
    /// tolerance.
    func retains(_ position: SIMD3<Double>) -> Bool {
        signedDistance(to: position) >= -tolerance
    }
}
