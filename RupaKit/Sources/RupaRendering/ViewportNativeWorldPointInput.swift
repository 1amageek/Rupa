import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// Native input owner for the three handle gestures whose drag geometry is a
/// world point rather than a screen distance or angle.
///
/// The prepared record is captured at press and never re-read from a later
/// frame. `query(displayedCanvas:)` names the single plane the mounted camera
/// is asked to intersect for this update, `value(for:...)` turns that frame's
/// two world points into the route's preview value, and `commit(value:...)`
/// converts the preview into the route's drag target exactly once, at release.
///
/// The plane is named per update rather than retained at press: the canvas
/// plane a projection mode displays can change while the button is held, and a
/// plane retained from the press would then be edge-on to the camera and refuse
/// every later sample until the release. Naming it per update keeps both ends
/// of one sample on the same plane, so the delta is always self-consistent.
struct ViewportNativeWorldPointInput: Sendable {
    /// The one native camera query this role needs for each drag update.
    enum Query: Equatable, Sendable {
        /// A fixed world plane through `origin`. The pattern and bridge handles
        /// drag inside the canvas plane the projection mode displays, moved to
        /// pass through the handle's own world point.
        case worldPlane(origin: Point3D, normal: Vector3D)
        /// The plane through `anchor` perpendicular to the mounted frame's view
        /// direction. Only the mounted frame knows that direction, so the
        /// construction-plane handles name the anchor and let the frame state
        /// the normal.
        case viewPlane(anchor: Point3D)
    }

    /// The mounted frame's answer to that query, read back by the viewport.
    struct Sample: Equatable, Sendable {
        let start: Point3D
        let current: Point3D
    }

    /// The preview this route's handles are redrawn at until the release
    /// resolves. Each case carries exactly what the overlay producer needs and
    /// nothing that depends on a screen projection.
    enum Value: Equatable, Sendable {
        case constructionPlane(origin: Point3D, normal: Vector3D)
        case patternArrayCurvePathPoint(Point3D)
        case bridgeCurveEndpoint(endpoint: BridgeCurveEndpoint, parameter: Double)
    }

    /// The document mutation a released gesture authorizes.
    enum Commit: Sendable {
        case constructionPlane(ViewportConstructionPlaneDragTarget)
        case patternArrayCurvePathPoint(ViewportPatternArrayCurvePathPointDragTarget)
        case bridgeCurveEndpoint(ViewportBridgeCurveEndpointDragTarget)
    }

    /// A world move below this distance is numerical noise, so the release
    /// writes no undo step for it.
    static let minimumWorldChange = 1.0e-12
    /// The same floor for a curve parameter, which is normalized rather than
    /// measured in metres.
    static let minimumParameterChange = 1.0e-8
    /// A normal handle dragged this close to its origin names no direction, so
    /// the update is refused instead of reporting an arbitrary plane.
    static let minimumNormalLength = 1.0e-10

    let record: ViewportSpatialInteractionRecord

    /// Whether this owner answers for the prepared route.
    ///
    /// The press, hover, update and release paths all re-read this predicate,
    /// so a route can never be half-claimed.
    static func claims(_ target: ViewportSpatialPreparedInteractionTarget) -> Bool {
        switch target {
        case .constructionPlane, .patternArrayCurvePathPoint, .bridgeCurveEndpoint: true
        default: false
        }
    }

    init?(record: ViewportSpatialInteractionRecord) throws {
        guard Self.claims(record.target) else { return nil }
        try Self.validate(record.target)
        self.record = record
    }

    var identity: ViewportSpatialHandleIdentity { record.identity }

    /// The plane this update asks the mounted frame to intersect.
    ///
    /// `displayedCanvas` is the plane the current projection mode draws its
    /// canvas on. It is passed in rather than stored because the mode can
    /// change mid-drag; see the type's note.
    func query(displayedCanvas: ViewportCanvasPlane) throws -> Query {
        switch record.target {
        case .constructionPlane(let identity, let origin, _, let normalEnd, _):
            switch identity.handle {
            case .origin: return .viewPlane(anchor: origin)
            case .normal: return .viewPlane(anchor: normalEnd)
            }
        case .patternArrayCurvePathPoint(let source):
            return .worldPlane(
                origin: try Self.basePoint(of: source),
                normal: try Self.canvasNormal(displayedCanvas)
            )
        case .bridgeCurveEndpoint(let handle, let modelTransform):
            return .worldPlane(
                origin: Self.worldPoint(of: handle, modelTransform: modelTransform),
                normal: try Self.canvasNormal(displayedCanvas)
            )
        default:
            throw RealityViewportSpatialBatch.invalid(
                "The world-point owner does not claim this prepared route."
            )
        }
    }

    /// Turns one frame answer into this route's preview value.
    ///
    /// Every refusal is typed and none is clamped: a clamped drag would preview
    /// a plane, point, or curve parameter the pointer never named.
    func value(
        for sample: Sample,
        document: DesignDocument,
        ruler: RulerConfiguration,
        snapOptions: SnapResolutionOptions?
    ) throws -> Value {
        guard sample.start.isFinite, sample.current.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A world-point sample is not finite.")
        }
        let delta = Self.vector(from: sample.start, to: sample.current)
        guard delta.isFinite else {
            throw RealityViewportSpatialBatch.invalid("A world-point delta is not finite.")
        }
        switch record.target {
        case .constructionPlane(let identity, let origin, let normal, let normalEnd, _):
            let dragged: ViewportConstructionPlaneDragTarget
            switch identity.handle {
            case .origin:
                dragged = ViewportConstructionPlaneDragTarget(
                    constructionPlaneID: identity.constructionPlaneID,
                    sceneNodeID: identity.sceneNodeID,
                    handle: identity.handle,
                    origin: Self.offset(origin, by: delta),
                    normal: normal
                )
            case .normal:
                let movedEnd = Self.offset(normalEnd, by: delta)
                let draggedNormal = Self.vector(from: origin, to: movedEnd)
                guard draggedNormal.isFinite,
                      draggedNormal.length > Self.minimumNormalLength else {
                    throw RealityViewportSpatialBatch.invalid(
                        "A construction-plane normal handle collapsed onto its origin."
                    )
                }
                dragged = ViewportConstructionPlaneDragTarget(
                    constructionPlaneID: identity.constructionPlaneID,
                    sceneNodeID: identity.sceneNodeID,
                    handle: identity.handle,
                    origin: origin,
                    normal: draggedNormal
                )
            }
            let snapped = ViewportConstructionPlaneDragSnapResolver().snappedTarget(
                dragged, document: document, ruler: ruler, options: snapOptions
            )
            guard snapped.origin.isFinite, snapped.normal.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "A snapped construction-plane handle is not finite."
                )
            }
            return .constructionPlane(origin: snapped.origin, normal: snapped.normal)

        case .patternArrayCurvePathPoint(let source):
            let point = Self.offset(try Self.basePoint(of: source), by: delta)
            guard point.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "A pattern curve path point is not finite."
                )
            }
            return .patternArrayCurvePathPoint(point)

        case .bridgeCurveEndpoint(let handle, let modelTransform):
            // The bridge curve lives in its sketch plane, so the world delta is
            // carried back through the placement before it is applied to the
            // authored 2D point. A placement that cannot be inverted is refused
            // rather than answered with the unmapped world delta.
            guard let localDelta = modelTransform.viewportInverseTransformedVector(delta) else {
                throw RealityViewportSpatialBatch.invalid(
                    "A bridge curve placement cannot map the world delta into its sketch plane."
                )
            }
            let nearPoint = Point2D(
                x: handle.point.x + localDelta.x,
                y: handle.point.y + localDelta.z
            )
            guard nearPoint.x.isFinite, nearPoint.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "A bridge curve endpoint sample is not finite."
                )
            }
            let projection = try BridgeCurveEndpointParameterProjectionService().projection(
                for: handle.endpoint,
                featureID: handle.featureID,
                near: nearPoint,
                in: document
            )
            guard projection.parameter.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "A bridge curve endpoint parameter is not finite."
                )
            }
            return .bridgeCurveEndpoint(
                endpoint: projection.endpoint, parameter: projection.parameter
            )

        default:
            throw RealityViewportSpatialBatch.invalid(
                "The world-point owner does not claim this prepared route."
            )
        }
    }

    /// Converts the release preview into this route's drag target.
    ///
    /// Returns `nil` when the gesture left the handle where it started, so a
    /// released press that moved nothing writes no undo step. A value that
    /// belongs to a different route is a typed refusal, never a silent drop.
    func commit(value: Value, document: DesignDocument) throws -> Commit? {
        switch (record.target, value) {
        case (
            .constructionPlane(let identity, let origin, let normal, _, _),
            .constructionPlane(let draggedOrigin, let draggedNormal)
        ):
            switch identity.handle {
            case .origin:
                guard Self.distance(origin, draggedOrigin) > Self.minimumWorldChange else {
                    return nil
                }
            case .normal:
                guard Self.distance(normal, draggedNormal) > Self.minimumWorldChange else {
                    return nil
                }
            }
            return .constructionPlane(ViewportConstructionPlaneDragTarget(
                constructionPlaneID: identity.constructionPlaneID,
                sceneNodeID: identity.sceneNodeID,
                handle: identity.handle,
                origin: draggedOrigin,
                normal: draggedNormal
            ))

        case (.patternArrayCurvePathPoint(let source), .patternArrayCurvePathPoint(let point)):
            guard Self.distance(try Self.basePoint(of: source), point) > Self.minimumWorldChange else {
                return nil
            }
            return .patternArrayCurvePathPoint(ViewportPatternArrayCurvePathPointDragTarget(
                sourceID: source.sourceID,
                pointIndex: source.pointIndex,
                point: point
            ))

        case (
            .bridgeCurveEndpoint(let handle, _),
            .bridgeCurveEndpoint(let endpoint, let parameter)
        ):
            // The press pinned the evaluation snapshot, so the authored
            // endpoint still resolves at release. A failure here is a refusal
            // of the gesture, not a reason to commit an unmeasured move.
            let base = try BridgeCurveEndpointParameterProjectionService().parameter(
                for: handle.endpoint, featureID: handle.featureID, in: document
            )
            guard base.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "A bridge curve endpoint baseline parameter is not finite."
                )
            }
            guard abs(parameter - base) > Self.minimumParameterChange else { return nil }
            return .bridgeCurveEndpoint(ViewportBridgeCurveEndpointDragTarget(
                sourceID: handle.sourceID, role: handle.role, endpoint: endpoint
            ))

        case (.constructionPlane, _), (.patternArrayCurvePathPoint, _), (.bridgeCurveEndpoint, _):
            throw RealityViewportSpatialBatch.invalid(
                "A world-point value does not answer the pressed handle."
            )
        default:
            throw RealityViewportSpatialBatch.invalid(
                "The world-point owner does not claim this prepared route."
            )
        }
    }

    // MARK: - Validation

    private static func validate(_ target: ViewportSpatialPreparedInteractionTarget) throws {
        switch target {
        case .constructionPlane(_, let origin, let normal, let normalEnd, let corners):
            guard origin.isFinite, normal.isFinite, normalEnd.isFinite,
                  corners.allSatisfy({ $0.isFinite }) else {
                throw RealityViewportSpatialBatch.invalid(
                    "A construction-plane handle is not finite."
                )
            }
            let guide = vector(from: origin, to: normalEnd)
            guard guide.isFinite, guide.length > minimumNormalLength else {
                throw RealityViewportSpatialBatch.invalid(
                    "A construction-plane normal handle has no guide length."
                )
            }
        case .patternArrayCurvePathPoint(let source):
            _ = try basePoint(of: source)
        case .bridgeCurveEndpoint(let handle, let modelTransform):
            guard handle.point.x.isFinite, handle.point.y.isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "A bridge curve endpoint point is not finite."
                )
            }
            guard worldPoint(of: handle, modelTransform: modelTransform).isFinite else {
                throw RealityViewportSpatialBatch.invalid(
                    "A bridge curve endpoint placement is not finite."
                )
            }
        default:
            throw RealityViewportSpatialBatch.invalid(
                "The world-point owner does not claim this prepared route."
            )
        }
    }

    /// The authored point the pattern handle drags, validated at press so no
    /// later update indexes outside the prepared path.
    private static func basePoint(
        of source: ViewportPatternAffordanceSource.CurvePathPointHandle
    ) throws -> Point3D {
        guard source.pointIndex >= 0, source.pointIndex < source.pathPoints.count else {
            throw RealityViewportSpatialBatch.invalid(
                "A pattern curve point index is out of bounds."
            )
        }
        let point = source.pathPoints[source.pointIndex]
        guard point.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "A pattern curve path point is not finite."
            )
        }
        return point
    }

    private static func worldPoint(
        of handle: BridgeCurveEndpointHandle, modelTransform: Transform3D
    ) -> Point3D {
        modelTransform.viewportTransformedPoint(
            Point3D(x: handle.point.x, y: 0.0, z: handle.point.y)
        )
    }

    private static func canvasNormal(_ plane: ViewportCanvasPlane) throws -> Vector3D {
        guard let normal = plane.normal, normal.isFinite, normal.length > minimumNormalLength else {
            throw RealityViewportSpatialBatch.invalid(
                "The displayed canvas plane names no normal."
            )
        }
        return normal
    }

    // MARK: - Math

    private static func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(x: end.x - start.x, y: end.y - start.y, z: end.z - start.z)
    }

    private static func offset(_ point: Point3D, by vector: Vector3D) -> Point3D {
        Point3D(x: point.x + vector.x, y: point.y + vector.y, z: point.z + vector.z)
    }

    private static func distance(_ lhs: Point3D, _ rhs: Point3D) -> Double {
        vector(from: lhs, to: rhs).length
    }

    private static func distance(_ lhs: Vector3D, _ rhs: Vector3D) -> Double {
        Vector3D(x: rhs.x - lhs.x, y: rhs.y - lhs.y, z: rhs.z - lhs.z).length
    }
}
