import RupaCore
import RupaViewportScene

/// Which transform the object gizmo offers and the frame it offers it in.
///
/// Without a configuration the gizmo keeps its combined form (world-aligned arrows, rings and axis
/// scale spheres at the selection center). A Move, Rotate or Scale mode shows that transform's
/// handles only, in the resolved frame, adding the plane, screen and uniform handles the mode owns;
/// a constraint narrows them to one axis, one plane, the screen or uniform scale. A mode scales
/// about its pivot, so one-sided scale belongs to the combined gizmo only.
public struct ViewportTransformGizmoConfiguration: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case move, rotate, scale
    }

    public enum Constraint: Equatable, Sendable {
        case axis(SceneTransformAxis)
        case plane(normal: SceneTransformAxis)
        /// Move in, or turn about, the view plane.
        case screen
        /// Scale all axes by one factor.
        case uniform
    }

    /// The steps a drag snaps to; `nil` fields leave that measure free.
    public struct Increments: Equatable, Sendable {
        public var distanceMeters: Double?
        public var angleRadians: Double?
        public var factor: Double?

        public init(distanceMeters: Double? = nil, angleRadians: Double? = nil, factor: Double? = nil) {
            self.distanceMeters = distanceMeters
            self.angleRadians = angleRadians
            self.factor = factor
        }
    }

    public var mode: Mode
    public var frame: SceneTransformFrame
    public var constraint: Constraint?
    public var increments: Increments?

    public init(mode: Mode, frame: SceneTransformFrame, constraint: Constraint? = nil, increments: Increments? = nil) {
        self.mode = mode
        self.frame = frame
        self.constraint = constraint
        self.increments = increments
    }

    func shows(_ action: ViewportAffordanceAction) -> Bool {
        switch action {
        case .translate(let axis):
            return mode == .move && admits(axis: axis)
        case .translatePlane(let normal):
            return mode == .move && admits(plane: normal)
        case .translateScreen:
            return mode == .move && (constraint == nil || constraint == .screen)
        case .rotate(let axis):
            return mode == .rotate && admits(axis: axis)
        case .rotateScreen:
            return mode == .rotate && constraint == .screen
        case .centerScale(let axis):
            return mode == .scale && admits(axis: axis)
        case .scalePlane(let normal):
            return mode == .scale && admits(plane: normal)
        case .uniformScale:
            return mode == .scale && (constraint == nil || constraint == .uniform)
        default:
            // Box resize and topology handles belong to the combined gizmo, not to a transform mode.
            return false
        }
    }

    private func admits(axis: ViewportCoordinateAxis) -> Bool {
        constraint == nil || constraint == .axis(Self.axis(axis))
    }

    private func admits(plane normal: ViewportCoordinateAxis) -> Bool {
        constraint == nil || constraint == .plane(normal: Self.axis(normal))
    }

    static func axis(_ axis: ViewportCoordinateAxis) -> SceneTransformAxis {
        switch axis {
        case .x: .x
        case .y: .y
        case .z: .z
        }
    }
}
