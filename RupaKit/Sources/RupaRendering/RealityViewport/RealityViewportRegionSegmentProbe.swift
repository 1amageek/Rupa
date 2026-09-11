import CoreGraphics

/// What a mounted frame reports about one projected segment walked across its
/// device pixels.
///
/// The walk exists because an edge candidate is decided at the first pixel the
/// frame does not hide it at, and that decision needs the frame's own lattice
/// rather than a sampling pitch: pixels make a short edge's admission
/// independent of zoom, and the frame's lattice makes it independent of
/// tessellation. `RupaRendering/DESIGN.md` owns that rule.
///
/// This owner reports only where the frame draws something. It never compares
/// a drawn depth against a candidate's own depth, because the slack that
/// comparison allows belongs to the resolver that owns the candidate. A
/// consumer rejecting the reported pixel resumes the same walk one step later
/// instead of restarting it.
struct RealityViewportRegionSegmentProbe {
    /// The first step of the walk that draws anything.
    struct Drawn {
        /// The step index, which is also the step a rejecting consumer
        /// resumes one past.
        let step: Int
        /// Where the step's sample sits along the segment the caller gave,
        /// as a fraction of that whole segment rather than of the part
        /// surviving the rectangle. The consumer interpolates its own depth
        /// at this fraction under the mapping the frame's projection implies.
        let fraction: Double
        let triangle: MeshSourcePresentationTriangle
        /// The linear view-space depth the frame draws that triangle at.
        let depth: Double
    }

    /// Device-pixel steps the walk has to take. Zero means it has none to
    /// take — either the segment leaves no pixel inside the rectangle, or the
    /// frame draws nothing anywhere — which is a different answer from a walk
    /// that took its steps and found none of them drawn.
    let stepCount: Int
    let drawn: Drawn?
}
