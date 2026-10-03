import RupaCore

/// One edge's continuity badge, drawn while a command that sets each boundary's continuity is open
/// (Plasticity's round G0/G1/G2 badges of Refit Face, XNURBS, Align Surface and Patch): `label`
/// beside the middle of the edge, a click on it reported through the viewport's continuity-badge
/// callback with `target`.
public struct ViewportContinuityBadge: Equatable, Hashable, Sendable {
    /// The boundary the badge sets: an edge of a body, or a curve object.
    public let target: SelectionTarget
    /// The continuity it shows, `G0`, `G1`, `G2` or `Free`.
    public let label: String

    public init(target: SelectionTarget, label: String) {
        self.target = target
        self.label = label
    }
}
