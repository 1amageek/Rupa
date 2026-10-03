import RupaCore

/// An angle of the running dialog the viewport offers as a handle turning about a curve, as
/// Plasticity's white circle (Pipe's angle) or its sweep gizmo (twist): a circle about the curve's
/// tangent at its anchor, the handle on it turned by the angle from the anchor's reference
/// direction, which a drag turns about the tangent.
public struct ViewportDialogAngleHandle: Equatable, Sendable {
    /// The dialog's name for the angle, which a drag reports back.
    public var id: String
    /// The curve the circle stands across: its start or its end (an offset along the guide is
    /// not used).
    public var anchor: ViewportDialogValueHandle.Anchor
    /// The circle's radius; nil for a tenth of the curve's drawn length.
    public var radiusMeters: Double?
    public var angleRadians: Double

    public init(id: String, anchor: ViewportDialogValueHandle.Anchor, radiusMeters: Double?, angleRadians: Double) {
        self.id = id
        self.anchor = anchor
        self.radiusMeters = radiusMeters
        self.angleRadians = angleRadians
    }
}

/// A dialog angle a drag of its handle set.
public struct ViewportDialogAngleDragTarget: Equatable, Sendable {
    public var id: String
    public var angleRadians: Double

    public init(id: String, angleRadians: Double) {
        self.id = id
        self.angleRadians = angleRadians
    }
}
