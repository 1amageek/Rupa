import SwiftCAD

/// One point picked in the viewport for a command that asks for a location (an array center, a
/// placement reference): the same snap, surface and construction-plane resolution Measure uses.
public enum ViewportPointPick: Equatable, Sendable {
    case point(Point3D)
    /// The click resolved no point; the message says why.
    case refused(String)
}
