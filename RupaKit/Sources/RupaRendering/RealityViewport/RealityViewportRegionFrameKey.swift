import CoreGraphics
import RupaViewportScene

/// The mounted-frame identity one region visibility raster stays valid for.
///
/// `RealityViewport/DESIGN.md` owns the membership, and the rule behind it is
/// that a region answer must agree with what the same frame draws. So every
/// input deciding *which* triangle a device pixel draws is a member, and
/// nothing deciding only how that triangle is shaded is. Selection, preview,
/// hover and material colour move a surface between materials without moving
/// it in front of or behind another, so the appearance value itself is not a
/// member; only the back-face culling that appearance derives is.
///
/// The retained plan and the render origin are absent for a different reason:
/// a viewport instance is prepared once against one plan and one origin and
/// never receives a second, so neither can change under a live raster.
struct RealityViewportRegionFrameKey: Equatable {
    /// The camera revision the frame applied, which is what a query's own
    /// revision is matched against before the raster is ever consulted.
    let appliedViewportRevision: UInt64
    let appliedLayout: ViewportLayout
    let appliedDisplayScale: CGFloat
    /// Bumped when a derived camera calibration differs from the one it
    /// replaces, which is the only way the projection can move without the
    /// layout or the revision moving with it. It counts differences rather
    /// than derivations because the frame re-derives an identical calibration
    /// on every appearance-only update, and a drag republishes one of those
    /// per pointer move.
    let calibrationGeneration: UInt64
    let section: RealityViewportSectionHalfSpace?
    let cullsBackfaces: Bool
    let geometryRootEnabled: Bool
}
