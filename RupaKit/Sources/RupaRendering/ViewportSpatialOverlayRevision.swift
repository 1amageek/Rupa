/// Non-observable identity storage: comparison during body evaluation cannot
/// invalidate that body. All access stays within the viewport's main actor.
@MainActor
final class ViewportSpatialOverlayRevision {
    private var key: ViewportSpatialOverlayChangeKey?
    private var value: UInt64

    init(initialValue: UInt64 = 0) {
        value = initialValue
    }

    func revision(for next: ViewportSpatialOverlayChangeKey) throws(MeshSourcePresentationRenderError) -> UInt64 {
        guard next.slotWidthMeters.isFinite,
              next.sketchVertexOffsetDistanceMeters.isFinite,
              next.edgeOffsetDistanceMeters.isFinite else {
            throw .init(code: .invalidLimit, message: "Spatial overlay guide dimensions must be finite.")
        }
        if key == next { return value }
        guard value < .max else {
            throw .init(code: .sizeOverflow, message: "Spatial overlay revision is exhausted.")
        }
        value += 1
        key = next
        return value
    }
}
