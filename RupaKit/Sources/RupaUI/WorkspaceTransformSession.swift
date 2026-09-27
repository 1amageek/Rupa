import Foundation
import RupaCore
import RupaRendering
import SwiftCAD

/// Move, Rotate or Scale in progress: the objects, the frame options, the constraint and any
/// freestyle points collected so far.
///
/// The session stays open across drags, typed values and freestyle motions so each of them is one
/// `transformSceneNodes` command in the same frame; Return or Escape ends it.
struct WorkspaceTransformSession: Equatable, Sendable {
    typealias Mode = ViewportTransformGizmoConfiguration.Mode
    typealias Constraint = ViewportTransformGizmoConfiguration.Constraint

    /// What the next viewport point pick is for.
    enum PointRole: Equatable, Sendable {
        case pivot
        case freestyle
    }

    /// The whole-object selection the session transforms, in selection order.
    let sceneNodeIDs: [SceneNodeID]
    var mode: Mode
    var pivotMode: SceneTransformPivotMode = .boundingBox
    var orientation: SceneTransformOrientation = .world
    /// A pivot the user placed with V; it overrides the pivot mode.
    var pickedPivot: SceneTransformFrame?
    var constraint: Constraint?
    /// Transform instances inversely: component instances of moved definitions stay in place.
    var compensatesInstances = false
    /// Whether drags snap to the increments.
    var snapsToIncrements = true
    /// The point pick the session is waiting for, if any.
    var pendingPoint: PointRole?
    /// Freestyle points picked so far; empty unless freestyle is running.
    var freestylePoints: [Point3D] = []
    /// The frame last resolved for the current document and options.
    var frame: SceneTransformFrame?
    /// Rotate's typed axis, in frame components; an axis constraint sets it to that axis.
    var rotationAxis = Vector3D(x: 0, y: 0, z: 1)
    /// Freestyle Scale scales every direction about the axis start instead of along the axis.
    var freestyleUniform = false
    /// Edges, faces or vertices of one body the session moves, rotates or scales instead of whole
    /// objects; a Move becomes the kernel's direct edit of that kind, and a Rotate or Scale its
    /// topology transform.
    var topologyTargets: [SelectionTarget] = []
    /// What `topologyTargets` are.
    var topologyKind: BodyTopologyMoveKind = .edges
    /// The world transform of the targets' body, to express a world motion in its frame.
    var topologyBodyWorldTransform = Transform3D.identity

    init(sceneNodeIDs: [SceneNodeID], mode: Mode) {
        self.sceneNodeIDs = sceneNodeIDs
        self.mode = mode
    }

    /// Resolves the frame for `metadata` with the selection's measured world bounds.
    mutating func resolveFrame(
        metadata: ProductMetadata,
        constructionPlane: SketchPlane?,
        selectionBounds: MeasurementResult.Bounds?
    ) throws {
        frame = try SceneTransformFrameResolver().frame(
            .init(
                sceneNodeIDs: sceneNodeIDs,
                pivotMode: pivotMode,
                orientation: orientation,
                pickedPivot: pickedPivot,
                constructionPlane: constructionPlane,
                selectionBounds: selectionBounds
            ),
            metadata: metadata
        )
    }

    /// The gizmo the viewport draws, once a frame is resolved and no point pick is pending.
    func gizmo(distanceStepMeters: Double) -> ViewportTransformGizmoConfiguration? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Move Edges, Faces and Vertices have no gizmo drag; the
        // viewport's transform gizmo previews whole-object placement only. Production path: typed
        // values and freestyle points reach `command(worldDelta:)`. Done when a gizmo drag
        // previews the moved body and commits the direct edit.
        guard let frame, pendingPoint == nil, topologyTargets.isEmpty else { return nil }
        let increments = snapsToIncrements
            ? ViewportTransformGizmoConfiguration.Increments(
                distanceMeters: distanceStepMeters,
                angleRadians: 15 * .pi / 180,
                factor: 0.05
            )
            : nil
        return ViewportTransformGizmoConfiguration(mode: mode, frame: frame, constraint: constraint, increments: increments)
    }

    /// Switches to `mode`; the key of the current mode toggles that mode's own constraint instead
    /// (G: screen in Move and Rotate, S: uniform in Scale).
    mutating func press(mode next: Mode) {
        guard next == mode else {
            mode = next
            constraint = nil
            freestylePoints = []
            if pendingPoint == .freestyle { pendingPoint = nil }
            return
        }
        switch mode {
        case .move, .rotate: toggle(.screen)
        case .scale: toggle(.uniform)
        }
    }

    /// X/Y/Z constrain to an axis; with Shift, to the plane perpendicular to it (Move and Scale).
    mutating func press(axis: SceneTransformAxis, plane: Bool) {
        if plane {
            guard mode != .rotate else { return }
            toggle(.plane(normal: axis))
        } else {
            toggle(.axis(axis))
            if mode == .rotate, constraint == .axis(axis) {
                rotationAxis = Vector3D(x: axis == .x ? 1 : 0, y: axis == .y ? 1 : 0, z: axis == .z ? 1 : 0)
            }
        }
    }

    private mutating func toggle(_ next: Constraint) {
        constraint = constraint == next ? nil : next
    }

    /// Starts freestyle: the next picks are its points.
    mutating func beginFreestyle() {
        freestylePoints = []
        pendingPoint = .freestyle
    }

    /// The number of points the current mode's freestyle form takes.
    var freestylePointCount: Int {
        switch mode {
        case .move: 2
        case .rotate: 4
        case .scale: 3
        }
    }

    /// Adds a freestyle point and returns the world motion once the form has all its points.
    mutating func addFreestylePoint(_ point: Point3D) throws -> Transform3D? {
        freestylePoints.append(point)
        guard freestylePoints.count == freestylePointCount else { return nil }
        let points = freestylePoints
        freestylePoints = []
        pendingPoint = nil
        switch mode {
        case .move:
            return try SceneTransformMotion.freestyleMove(from: points[0], to: points[1])
        case .rotate:
            return try SceneTransformMotion.freestyleRotation(
                axisStart: points[0], axisEnd: points[1], reference: points[2], target: points[3]
            )
        case .scale:
            let ratio = try SceneTransformMotion.freestyleRatio(axisStart: points[0], axisEnd: points[1], toward: points[2])
            return try freestyleScale(axisStart: points[0], axisEnd: points[1], ratio: ratio)
        }
    }

    /// Whether freestyle Scale has its axis and waits for a ratio point or a typed ratio or length.
    var hasFreestyleScaleAxis: Bool {
        mode == .scale && pendingPoint == .freestyle && freestylePoints.count == 2
    }

    /// Freestyle Scale by a typed ratio, once its axis is picked.
    mutating func typedFreestyleScale(ratio: Double) throws -> Transform3D {
        guard hasFreestyleScaleAxis else {
            throw EditorError(code: .commandInvalid, message: "Freestyle Scale needs its axis start and end first.")
        }
        let points = freestylePoints
        let motion = try freestyleScale(axisStart: points[0], axisEnd: points[1], ratio: ratio)
        freestylePoints = []
        pendingPoint = nil
        return motion
    }

    /// Freestyle Scale that makes the picked axis `length` long.
    mutating func typedFreestyleScale(length: Double) throws -> Transform3D {
        guard hasFreestyleScaleAxis else {
            throw EditorError(code: .commandInvalid, message: "Freestyle Scale needs its axis start and end first.")
        }
        let ratio = try SceneTransformMotion.freestyleRatio(
            axisStart: freestylePoints[0], axisEnd: freestylePoints[1], length: length
        )
        return try typedFreestyleScale(ratio: ratio)
    }

    private func freestyleScale(axisStart: Point3D, axisEnd: Point3D, ratio: Double) throws -> Transform3D {
        if freestyleUniform {
            return try SceneTransformMotion.uniformScale(in: .world(at: axisStart), factor: ratio)
        }
        return try SceneTransformMotion.freestyleScale(axisStart: axisStart, axisEnd: axisEnd, ratio: ratio)
    }

    /// Places the pivot at `point`, with its axes from the surface normal there when there is one.
    mutating func pickPivot(at point: Point3D, normal: Vector3D?) throws {
        pickedPivot = try normal.map { try SceneTransformFrame(origin: point, normal: $0) } ?? .world(at: point)
        pendingPoint = nil
    }

    /// Removes a picked pivot; an orientation that needed it falls back to the world.
    mutating func removePivot() {
        pickedPivot = nil
        if orientation == .pivot { orientation = .world }
    }

    /// Steps the orientation, skipping the pivot orientation while no pivot is picked.
    mutating func cycleOrientation() {
        orientation = orientation.next
        if orientation == .pivot, pickedPivot == nil {
            orientation = orientation.next
        }
    }

    /// The typed Move by frame components, as one world motion.
    func typedMove(_ components: Vector3D) throws -> Transform3D {
        try SceneTransformMotion.translation(in: try requiredFrame(), by: components)
    }

    /// The typed Rotate by degrees about `rotationAxis` through the pivot, as one world motion.
    func typedRotation(degrees: Double) throws -> Transform3D {
        let frame = try requiredFrame()
        guard degrees.isFinite else {
            throw EditorError(code: .commandInvalid, message: "A rotation angle must be finite.")
        }
        let axis = frame.worldVector(rotationAxis)
        guard axis.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "A rotation axis must not be zero.")
        }
        return try Transform3D.rotation(axis: axis, angleRadians: degrees * .pi / 180, about: frame.origin)
    }

    /// Chooses the pivot mode; a picked pivot gives way to it.
    mutating func choose(pivotMode: SceneTransformPivotMode) {
        self.pivotMode = pivotMode
        removePivot()
    }

    /// The typed Scale by frame-axis factors, as one world motion.
    func typedScale(_ factors: Vector3D) throws -> Transform3D {
        try SceneTransformMotion.scale(in: try requiredFrame(), factors: factors)
    }

    /// The command applying `worldDelta` to the session's objects, or moving its edges, faces or
    /// vertices by the motion expressed in their body's frame: a Move by its translation, a Rotate
    /// or Scale by the whole motion.
    func command(worldDelta: Transform3D) throws -> EditorCommand {
        guard !topologyTargets.isEmpty else {
            return .transformSceneNodes(ids: sceneNodeIDs, worldDelta: worldDelta, compensatingInstances: compensatesInstances)
        }
        if mode != .move {
            let local = try topologyBodyWorldTransform.inverse().composed(with: worldDelta.composed(with: topologyBodyWorldTransform))
            return .transformBodyTopology(
                kind: topologyKind, targets: topologyTargets, motion: try TopologyMotionDecomposition.motion(local)
            )
        }
        let pivot = try requiredFrame().origin
        let world = try worldDelta.applied(to: pivot) - pivot
        let local = try topologyBodyWorldTransform.inverseApplyingLinearPart(to: world)
        guard local.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "\(topologyKind.title) needs a motion.")
        }
        let direction = try local.normalized(tolerance: ModelingTolerance.standard.distance)
        let distance = CADExpression.length(local.length, .meter)
        return switch topologyKind {
        case .edges: .moveBodyEdges(targets: topologyTargets, direction: direction, distance: distance)
        case .faces: .moveBodyFaces(targets: topologyTargets, direction: direction, distance: distance)
        case .vertices: .moveBodyVertices(targets: topologyTargets, direction: direction, distance: distance)
        }
    }

    /// The command a gizmo drag commits: the one world motion every dragged node received,
    /// applied to those nodes.
    func dragCommand(_ targets: [ViewportBodyPlacementDragTarget]) throws -> EditorCommand {
        guard let first = targets.first else {
            throw EditorError(code: .commandInvalid, message: "A transform drag moved no objects.")
        }
        func worldDelta(_ target: ViewportBodyPlacementDragTarget) throws -> Transform3D {
            let before = try target.baseParentWorldTransform.composed(with: target.baseLocalTransform)
            let after = try target.baseParentWorldTransform.composed(with: target.localTransform)
            return try after.composed(with: try before.inverse())
        }
        let delta = try worldDelta(first)
        let tolerance = ModelingTolerance.standard.distance
        for target in targets.dropFirst() {
            let other = try worldDelta(target).matrix.values
            guard zip(delta.matrix.values, other).allSatisfy({ abs($0 - $1) <= tolerance }) else {
                throw EditorError(code: .commandInvalid, message: "A transform drag moved its objects by different motions.")
            }
        }
        return .transformSceneNodes(
            ids: targets.map(\.sceneNodeID),
            worldDelta: delta,
            compensatingInstances: compensatesInstances
        )
    }

    private func requiredFrame() throws -> SceneTransformFrame {
        guard let frame else {
            throw EditorError(code: .commandInvalid, message: "The transform frame is not resolved yet.")
        }
        return frame
    }

    var title: String {
        if !topologyTargets.isEmpty {
            return switch mode {
            case .move: topologyTargets.count == 1 ? topologyKind.singularTitle : topologyKind.title
            case .rotate: "Rotate \(topologyKind.noun)"
            case .scale: "Scale \(topologyKind.noun)"
            }
        }
        return switch mode {
        case .move: "Move"
        case .rotate: "Rotate"
        case .scale: "Scale"
        }
    }

    var constraintName: String {
        switch constraint {
        case nil: "Free"
        case .axis(let axis): axis.rawValue.uppercased()
        case .plane(let normal): "\(normal.rawValue.uppercased()) plane"
        case .screen: "Screen"
        case .uniform: "Uniform"
        }
    }

    var prompt: String {
        switch pendingPoint {
        case .pivot:
            return "\(title): click the pivot point. Esc cancels the pick."
        case .freestyle:
            let names: [String] = switch mode {
            case .move: ["start point", "end point"]
            case .rotate: ["axis start", "axis end", "reference point", "target point"]
            case .scale: ["axis start", "axis end", "ratio point"]
            }
            return "\(title) freestyle: click the \(names[freestylePoints.count]). Esc cancels."
        case nil where !topologyTargets.isEmpty:
            return "\(title): type the motion, or F for two points. W orientation, V pivot, Return or Esc finishes."
        case nil:
            return "\(title): drag the gizmo. X/Y/Z axis, Shift-X/Y/Z plane, W orientation, V pivot, F freestyle, Return or Esc finishes."
        }
    }
}
