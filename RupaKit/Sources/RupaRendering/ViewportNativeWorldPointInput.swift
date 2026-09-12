import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD

/// Native input owner for the handle gestures whose drag geometry is a world
/// point rather than a screen distance or angle.
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
        /// The displacement a surface handle has been dragged, stated in the
        /// record's own model space. The trim routes solve their parameter
        /// pair from it at release rather than previewing one, because the
        /// overlay redraws those handles from the same displacement.
        case surfaceHandleLocalDelta(Vector3D)
    }

    /// The document mutation a released gesture authorizes.
    enum Commit: Sendable {
        case constructionPlane(ViewportConstructionPlaneDragTarget)
        case patternArrayCurvePathPoint(ViewportPatternArrayCurvePathPointDragTarget)
        case bridgeCurveEndpoint(ViewportBridgeCurveEndpointDragTarget)
        case polySplineSurfaceVertex(ViewportPolySplineSurfaceVertexDragTarget)
        case surfaceControlPoint(ViewportSurfaceControlPointDragTarget)
        case surfaceTrimEndpoint(ViewportSurfaceTrimEndpointDragTarget)
        case surfaceTrimControlPoint(ViewportSurfaceTrimControlPointDragTarget)
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
    /// A surface parameter move below this is numerical noise. The surface
    /// domain is not normalized the way a curve parameter is, so this floor
    /// matches the world one rather than `minimumParameterChange`.
    static let minimumSurfaceParameterChange = 1.0e-12
    /// A trim tangent pair whose Gram determinant is at or below this spans no
    /// surface patch, so no parameter delta can be solved from it.
    static let minimumTrimGramDeterminant = 1.0e-18

    let record: ViewportSpatialInteractionRecord

    /// Whether this owner answers for the prepared route.
    ///
    /// The press, hover, update and release paths all re-read this predicate,
    /// so a route can never be half-claimed.
    static func claims(_ target: ViewportSpatialPreparedInteractionTarget) -> Bool {
        switch target {
        case .constructionPlane, .patternArrayCurvePathPoint, .bridgeCurveEndpoint: true
        // These two cases draw one handle per drag mode, so the record the
        // press resolved already names which handle was grabbed. The axis and
        // local-axis handles move along one world axis and belong to the axis
        // owner; only the planar handle resolves a world point.
        case .polySplineSurfaceVertex(let value): value.dragMode == .planar
        case .surfaceControlPoint(let value): value.dragMode == .planar
        case .surfaceTrimEndpoint, .surfaceTrimControlPoint: true
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
        case .polySplineSurfaceVertex(let handle):
            return try Self.handlePlane(
                localPoint: handle.point, modelTransform: handle.modelTransform,
                displayedCanvas: displayedCanvas
            )
        case .surfaceControlPoint(let handle):
            return try Self.handlePlane(
                localPoint: handle.point, modelTransform: handle.modelTransform,
                displayedCanvas: displayedCanvas
            )
        case .surfaceTrimEndpoint(let handle):
            return try Self.handlePlane(
                localPoint: handle.point, modelTransform: handle.modelTransform,
                displayedCanvas: displayedCanvas
            )
        case .surfaceTrimControlPoint(let handle):
            return try Self.handlePlane(
                localPoint: handle.point, modelTransform: handle.modelTransform,
                displayedCanvas: displayedCanvas
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

        case .polySplineSurfaceVertex(let handle):
            return .surfaceHandleLocalDelta(
                try Self.modelDelta(delta, in: handle.modelTransform)
            )

        case .surfaceControlPoint(let handle):
            return .surfaceHandleLocalDelta(
                try Self.modelDelta(delta, in: handle.modelTransform)
            )

        case .surfaceTrimEndpoint(let handle):
            return .surfaceHandleLocalDelta(
                try Self.modelDelta(delta, in: handle.modelTransform)
            )

        case .surfaceTrimControlPoint(let handle):
            return .surfaceHandleLocalDelta(
                try Self.modelDelta(delta, in: handle.modelTransform)
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

        case (.polySplineSurfaceVertex(let handle), .surfaceHandleLocalDelta(let delta)):
            guard Self.moves(delta) else { return nil }
            return .polySplineSurfaceVertex(ViewportPolySplineSurfaceVertexDragTarget(
                target: handle.target, deltaX: delta.x, deltaY: delta.y, deltaZ: delta.z
            ))

        case (.surfaceControlPoint(let handle), .surfaceHandleLocalDelta(let delta)):
            guard Self.moves(delta) else { return nil }
            return .surfaceControlPoint(ViewportSurfaceControlPointDragTarget(
                target: handle.target, deltaX: delta.x, deltaY: delta.y, deltaZ: delta.z
            ))

        case (.surfaceTrimEndpoint(let handle), .surfaceHandleLocalDelta(let delta)):
            guard Self.moves(delta) else { return nil }
            guard let moved = try Self.movedTrimUV(
                u: handle.u, v: handle.v, tangentU: handle.tangentU,
                tangentV: handle.tangentV, delta: delta
            ) else { return nil }
            return .surfaceTrimEndpoint(ViewportSurfaceTrimEndpointDragTarget(
                target: handle.target, endpoint: handle.endpoint, u: moved.u, v: moved.v
            ))

        case (.surfaceTrimControlPoint(let handle), .surfaceHandleLocalDelta(let delta)):
            guard Self.moves(delta) else { return nil }
            guard let moved = try Self.movedTrimUV(
                u: handle.u, v: handle.v, tangentU: handle.tangentU,
                tangentV: handle.tangentV, delta: delta
            ) else { return nil }
            return .surfaceTrimControlPoint(ViewportSurfaceTrimControlPointDragTarget(
                target: handle.target, controlPointIndex: handle.controlPointIndex,
                u: moved.u, v: moved.v
            ))

        case (.constructionPlane, _), (.patternArrayCurvePathPoint, _),
             (.bridgeCurveEndpoint, _), (.polySplineSurfaceVertex, _),
             (.surfaceControlPoint, _), (.surfaceTrimEndpoint, _),
             (.surfaceTrimControlPoint, _):
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
        case .polySplineSurfaceVertex(let handle):
            try validateHandle(
                localPoint: handle.point, modelTransform: handle.modelTransform
            )
        case .surfaceControlPoint(let handle):
            try validateHandle(
                localPoint: handle.point, modelTransform: handle.modelTransform
            )
        case .surfaceTrimEndpoint(let handle):
            try validateHandle(
                localPoint: handle.point, modelTransform: handle.modelTransform
            )
            try validateTrimParameters(
                u: handle.u, v: handle.v,
                tangentU: handle.tangentU, tangentV: handle.tangentV
            )
        case .surfaceTrimControlPoint(let handle):
            try validateHandle(
                localPoint: handle.point, modelTransform: handle.modelTransform
            )
            try validateTrimParameters(
                u: handle.u, v: handle.v,
                tangentU: handle.tangentU, tangentV: handle.tangentV
            )
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

    /// Validates a surface handle's drawn point and its placement.
    ///
    /// The placement must be invertible because every one of these routes
    /// commits a model-space displacement. Whether it inverts depends only on
    /// the transform's linear part, so the probe direction is arbitrary.
    private static func validateHandle(
        localPoint: Point3D, modelTransform: Transform3D
    ) throws {
        guard localPoint.isFinite,
              modelTransform.viewportTransformedPoint(localPoint).isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "A surface handle placement is not finite."
            )
        }
        guard modelTransform.viewportInverseTransformedVector(
            Vector3D(x: 1.0, y: 0.0, z: 0.0)
        ) != nil else {
            throw RealityViewportSpatialBatch.invalid(
                "A surface handle placement cannot map a world delta into model space."
            )
        }
    }

    /// Validates a trim handle's retained parameter pair and tangent basis at
    /// press.
    ///
    /// A degenerate tangent pair is refused here rather than dropped update by
    /// update, because a handle that can never resolve must not stay drawn and
    /// grabbable for the length of a gesture that commits nothing.
    private static func validateTrimParameters(
        u: Double, v: Double, tangentU: Vector3D, tangentV: Vector3D
    ) throws {
        guard u.isFinite, v.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "A surface trim handle parameter is not finite."
            )
        }
        _ = try trimGram(tangentU: tangentU, tangentV: tangentV)
    }

    private static func trimGram(
        tangentU: Vector3D, tangentV: Vector3D
    ) throws -> (uu: Double, uv: Double, vv: Double, determinant: Double) {
        guard tangentU.isFinite, tangentV.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "A surface trim handle tangent is not finite."
            )
        }
        let uu = tangentU.dot(tangentU)
        let uv = tangentU.dot(tangentV)
        let vv = tangentV.dot(tangentV)
        let determinant = uu * vv - uv * uv
        guard determinant.isFinite,
              abs(determinant) > minimumTrimGramDeterminant else {
            throw RealityViewportSpatialBatch.invalid(
                "A surface trim handle tangent pair spans no surface patch."
            )
        }
        return (uu, uv, vv, determinant)
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

    /// The plane a surface handle drags on: parallel to the displayed canvas
    /// plane and through the handle's own world point, so the grabbed handle
    /// stays under the pointer in perspective as well as in orthographic.
    private static func handlePlane(
        localPoint: Point3D,
        modelTransform: Transform3D,
        displayedCanvas: ViewportCanvasPlane
    ) throws -> Query {
        .worldPlane(
            origin: modelTransform.viewportTransformedPoint(localPoint),
            normal: try canvasNormal(displayedCanvas)
        )
    }

    /// Carries a world displacement back into the record's model space.
    ///
    /// Every surface handle callback is authored in that space, so a
    /// placement that cannot be inverted is refused rather than answered with
    /// the unmapped world value.
    private static func modelDelta(
        _ delta: Vector3D, in modelTransform: Transform3D
    ) throws -> Vector3D {
        guard let localDelta = modelTransform.viewportInverseTransformedVector(delta) else {
            throw RealityViewportSpatialBatch.invalid(
                "A surface handle placement cannot map the world delta into model space."
            )
        }
        guard localDelta.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "A surface handle model-space delta is not finite."
            )
        }
        return localDelta
    }

    private static func moves(_ delta: Vector3D) -> Bool {
        abs(delta.x) > minimumWorldChange
            || abs(delta.y) > minimumWorldChange
            || abs(delta.z) > minimumWorldChange
    }

    /// Solves a model-space displacement against a trim handle's tangent pair
    /// for the parameter pair the release commits.
    ///
    /// Returns `nil` only when the solved pair does not move, which is the
    /// ordinary no-commit case. A tangent basis that cannot be solved is a
    /// typed refusal, raised here and at press.
    private static func movedTrimUV(
        u: Double, v: Double, tangentU: Vector3D, tangentV: Vector3D, delta: Vector3D
    ) throws -> (u: Double, v: Double)? {
        let gram = try trimGram(tangentU: tangentU, tangentV: tangentV)
        let moveU = delta.dot(tangentU)
        let moveV = delta.dot(tangentV)
        let deltaU = (moveU * gram.vv - moveV * gram.uv) / gram.determinant
        let deltaV = (gram.uu * moveV - gram.uv * moveU) / gram.determinant
        let movedU = u + deltaU
        let movedV = v + deltaV
        guard movedU.isFinite, movedV.isFinite else {
            throw RealityViewportSpatialBatch.invalid(
                "A solved surface trim parameter is not finite."
            )
        }
        guard abs(deltaU) > minimumSurfaceParameterChange
            || abs(deltaV) > minimumSurfaceParameterChange else { return nil }
        return (movedU, movedV)
    }
}
