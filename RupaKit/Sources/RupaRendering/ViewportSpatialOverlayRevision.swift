/// Non-observable identity storage: comparison during body evaluation cannot
/// invalidate that body. All access stays within the viewport's main actor.
///
/// The overlay revision advances on every change of the key; the base revision only when the key
/// changes in more than hover (`ViewportSpatialOverlayChangeKey.withoutHover`).
@MainActor
final class ViewportSpatialOverlayRevision {
    struct Revisions: Equatable {
        let overlay: UInt64
        let base: UInt64
    }

    private var key: ViewportSpatialOverlayChangeKey?
    private var baseKey: ViewportSpatialOverlayChangeKey?
    private var value: UInt64
    private var baseValue: UInt64

    init(initialValue: UInt64 = 0) {
        value = initialValue
        baseValue = initialValue
    }

    func revision(for next: ViewportSpatialOverlayChangeKey) throws(MeshSourcePresentationRenderError) -> UInt64 {
        try revisions(for: next).overlay
    }

    func revisions(for next: ViewportSpatialOverlayChangeKey) throws(MeshSourcePresentationRenderError) -> Revisions {
        guard next.slotWidthMeters.isFinite,
              next.sketchVertexOffsetDistanceMeters.isFinite,
              next.edgeOffsetDistanceMeters.isFinite,
              next.sketchCornerTreatmentHandle?.signedDistance.isFinite != false,
              next.nativeAxisValue?.isFinite != false,
              next.nativePatternValue?.isFinite != false else {
            throw .init(code: .invalidLimit, message: "Spatial overlay guide dimensions must be finite.")
        }
        if key == next { return Revisions(overlay: value, base: baseValue) }
        guard value < .max, baseValue < .max else {
            throw .init(code: .sizeOverflow, message: "Spatial overlay revision is exhausted.")
        }
        let nextBase = next.withoutHover
        if baseKey != nextBase {
            baseValue += 1
            baseKey = nextBase
        }
        value += 1
        key = next
        return Revisions(overlay: value, base: baseValue)
    }
}
