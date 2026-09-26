import SwiftCAD

/// Move Control Point's Proportional and Mirror options.
public struct SurfaceControlPointMoveOptions: Codable, Hashable, Sendable {
    /// Which control points besides the moved ones follow the move.
    public enum Proportional: String, Codable, Hashable, Sendable, CaseIterable {
        /// Only the selected control points move.
        case none
        /// Every control point of the surface follows by its falloff from the selection.
        case all
        /// Only the selected control points move, each by its falloff from the active one.
        case selected
    }

    /// The construction-plane axis the mirror plane is perpendicular to.
    public enum MirrorAxis: String, Codable, Hashable, Sendable, CaseIterable {
        case x, y, z
    }

    public var proportional: Proportional
    /// The falloff reach along U, in control-net steps.
    public var falloffU: Double
    /// The falloff reach along V, in control-net steps.
    public var falloffV: Double
    public var mirrorAxis: MirrorAxis?
    /// The construction plane the mirror axes belong to, in world coordinates.
    public var mirrorPlane: SketchPlane

    public init(
        proportional: Proportional = .none,
        falloffU: Double = 2,
        falloffV: Double = 2,
        mirrorAxis: MirrorAxis? = nil,
        mirrorPlane: SketchPlane = .xy
    ) {
        self.proportional = proportional
        self.falloffU = falloffU
        self.falloffV = falloffV
        self.mirrorAxis = mirrorAxis
        self.mirrorPlane = mirrorPlane
    }

    /// Whether the options change anything beyond moving the selected control points.
    public var isPlainMove: Bool {
        proportional == .none && mirrorAxis == nil
    }
}
