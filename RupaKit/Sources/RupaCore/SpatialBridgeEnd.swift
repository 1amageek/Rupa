import SwiftCAD

/// One end of a Bridge Curve between curves that do not share a sketch: a sketch curve or a
/// generated body edge, at `fraction` of its parameter (0 at its start, 1 at its end; a spline's
/// normalized knot domain). The bridge leaves the curve outward: forward past the middle,
/// backward before it.
public struct SpatialBridgeEnd: Codable, Equatable, Sendable {
    public var target: SelectionTarget
    public var fraction: Double

    public init(target: SelectionTarget, fraction: Double) {
        self.target = target
        self.fraction = fraction
    }
}
