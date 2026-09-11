import simd

/// Everything a region visibility raster needs to reproduce one mounted
/// frame's projection, clipping and visibility, with no RealityKit type in it.
///
/// The mounted frame derives this once, from the same camera components and
/// the same calibration its point queries use, and the raster then reads
/// nothing else. Keeping the reconstruction in a value rather than in the
/// raster is what lets the projection, the near clip, the back-face rule and
/// the depth bounds be exercised without a mounted display.
///
/// Coordinates are native scene space, so a CAD world position enters as
/// `position - renderOrigin`. `RealityViewport/DESIGN.md` owns the contract
/// this reconstructs and the reason it is reconstructed at all: RealityKit
/// vends no region query and no projection matrix, only a per-point
/// projection, so the frame samples that projection into an affine
/// camera-plane map and the raster replays it in `Double`.
struct RealityViewportRegionFrame {
    /// Native scene space to camera-local space. Taken once per frame from
    /// the camera entity, because a per-position `camera.convert` would run
    /// the same transform up to `maxPositionCount` times.
    let viewMatrix: simd_double4x4
    /// The CAD world origin the native scene is built around. A plan holds
    /// CAD world positions, and this is the only place they become native.
    let renderOrigin: SIMD3<Double>
    /// Camera-local origin in native scene space, which is the eye a
    /// perspective frame's back-face rule and near clip are written against.
    let eye: SIMD3<Double>
    /// Unit camera forward in native scene space, which is the direction an
    /// orthographic frame's rays travel and its back-face rule reads.
    let forward: SIMD3<Double>
    /// Camera-plane units per camera-local unit at `sampleDepth`.
    let step: Double
    /// The camera-local depth the camera-plane map was sampled at.
    let sampleDepth: Double
    let usesPerspectiveProjection: Bool
    /// Camera-plane coordinates to points, as the six affine coefficients the
    /// frame sampled through native projection and then inverted.
    let planeToPoints: (a: Double, b: Double, c: Double, d: Double,
                        tx: Double, ty: Double)
    let displayScale: Double
    let pixelWidth: Int
    let pixelHeight: Int
    /// The camera's own clipping interval, inclusive at both ends, in the
    /// linear view-space depth every native query reports.
    let nearDepth: Double
    let farDepth: Double
    let section: RealityViewportSectionHalfSpace?
    let cullsBackfaces: Bool

    /// The native scene position of a CAD world position.
    func nativeScene(x: Double, y: Double, z: Double) -> SIMD3<Double> {
        SIMD3<Double>(x - renderOrigin.x, y - renderOrigin.y,
                      z - renderOrigin.z)
    }

    /// The camera-local position of a native scene position.
    func cameraLocal(_ position: SIMD3<Double>) -> SIMD3<Double> {
        let transformed = viewMatrix * SIMD4<Double>(position, 1)
        return SIMD3<Double>(transformed.x, transformed.y, transformed.z)
    }

    /// The device-pixel position a camera-local point projects to, or `nil`
    /// when the projection is not finite there.
    ///
    /// A perspective frame divides by the camera-local depth, so the caller
    /// must have clipped the point to the near plane before asking. An
    /// orthographic frame never divides and accepts any depth.
    func projected(_ local: SIMD3<Double>) -> SIMD2<Double>? {
        let depth = -local.z
        let plane: SIMD2<Double>
        if usesPerspectiveProjection {
            guard depth > 0 else { return nil }
            plane = SIMD2<Double>(local.x * sampleDepth / (step * depth),
                                  local.y * sampleDepth / (step * depth))
        } else {
            plane = SIMD2<Double>(local.x / step, local.y / step)
        }
        let x = planeToPoints.a * plane.x + planeToPoints.c * plane.y
            + planeToPoints.tx
        let y = planeToPoints.b * plane.x + planeToPoints.d * plane.y
            + planeToPoints.ty
        guard x.isFinite, y.isFinite else { return nil }
        return SIMD2<Double>(x * displayScale, y * displayScale)
    }

    /// Whether a fragment's interpolated depth is inside the camera's own
    /// clipping interval. Both bounds are inclusive, matching
    /// `cameraDepthInterval(revision:)`, which is the single reader of that
    /// interval every other scope shares.
    func retainsDepth(_ depth: Double) -> Bool {
        depth >= nearDepth && depth <= farDepth
    }

    /// Whether a triangle faces away from the frame and is therefore not
    /// drawn. This is the per-triangle sign the native collision admission
    /// takes, evaluated exactly and in the same space.
    func culls(normal: SIMD3<Double>, firstPosition: SIMD3<Double>) -> Bool {
        guard cullsBackfaces else { return false }
        if usesPerspectiveProjection {
            return simd_dot(normal, firstPosition - eye) >= 0
        }
        return simd_dot(normal, forward) >= 0
    }
}
