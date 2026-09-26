import CoreGraphics
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD

/// The source retained by one transient measurement endpoint.
enum ViewportMeasurementEndpointSource: Equatable, Sendable {
    case snap(SnapCandidate)
    case presentation(occurrenceID: SceneOccurrenceID)
    case constructionPlane(SketchPlane)
    /// A point on a measured edge or curve, already anchored to it.
    case anchor(MeasurementAnchor)
}

/// The two anchored points Measure starts placing a dimension between, such as the ends of a
/// selected edge.
public struct ViewportMeasurementSeed: Equatable, Sendable {
    public var start: MeasuredCurvePoint
    public var end: MeasuredCurvePoint

    public init(start: MeasuredCurvePoint, end: MeasuredCurvePoint) {
        self.start = start
        self.end = end
    }
}

/// A finite world-space point accepted by the measurement resolver.
struct ViewportMeasurementEndpoint: Equatable, Sendable {
    let point: Point3D
    let source: ViewportMeasurementEndpointSource

    init(
        point: Point3D,
        source: ViewportMeasurementEndpointSource
    ) {
        self.point = point
        self.source = source
    }
}

struct ViewportMeasurementPresentationHit: Equatable, Sendable {
    let point: Point3D
    let occurrenceID: SceneOccurrenceID

    init(point: Point3D, occurrenceID: SceneOccurrenceID) {
        self.point = point
        self.occurrenceID = occurrenceID
    }
}

enum ViewportMeasurementResolutionFailure: Error, Equatable, Sendable {
    case noConstructionPlane
    case viewRayUnavailable
    case viewRayParallelToPlane
    case pointBehindPerspectiveCamera
    case nonFiniteEndpoint
    case presentationUnavailable(String)
    case snapFailed(String)

    var message: String {
        switch self {
        case .noConstructionPlane:
            "Choose a construction plane before measuring empty space."
        case .viewRayUnavailable:
            "The current viewport ray is unavailable."
        case .viewRayParallelToPlane:
            "The current view is parallel to the active construction plane."
        case .pointBehindPerspectiveCamera:
            "The selected point is behind the perspective camera."
        case .nonFiniteEndpoint:
            "The selected measurement point is not finite."
        case .presentationUnavailable(let message):
            "The displayed surface is unavailable: \(message)"
        case .snapFailed(let message):
            "Snap failed: \(message)"
        }
    }
}

struct ViewportMeasurementResolution: Equatable, Sendable {
    let endpoint: ViewportMeasurementEndpoint?
    let failure: ViewportMeasurementResolutionFailure?
    var warning: String? = nil

    init(
        endpoint: ViewportMeasurementEndpoint?,
        failure: ViewportMeasurementResolutionFailure? = nil
    ) {
        self.endpoint = endpoint
        self.failure = failure
    }
}

/// Resolves both hover and click using the same priority-ordered endpoint path.
struct ViewportMeasurementResolver: Sendable {
    init() {}

    func resolve(
        effectivePlane: SketchPlane?,
        snap: ViewportSnapResolution?,
        presentationHit: ViewportMeasurementPresentationHit?,
        planeIntersection: (SketchPlane) throws -> Point3D,
        validateWorldPoint: (Point3D) throws -> Void
    ) -> ViewportMeasurementResolution {
        if let failure = snap?.failureDescription {
            var fallback = resolve(
                effectivePlane: effectivePlane,
                snap: nil,
                presentationHit: presentationHit,
                planeIntersection: planeIntersection,
                validateWorldPoint: validateWorldPoint
            )
            fallback.warning = ViewportMeasurementResolutionFailure.snapFailed(failure).message
            return fallback
        }
        if let snapResult = snap?.result,
           let candidate = snapResult.selectedCandidate {
            if let worldPoint = snapResult.selectedWorldPoint {
                guard worldPoint.isFinite else {
                    return ViewportMeasurementResolution(endpoint: nil, failure: .nonFiniteEndpoint)
                }
                do {
                    try validateWorldPoint(worldPoint)
                } catch {
                    return ViewportMeasurementResolution(
                        endpoint: nil,
                        failure: Self.failure(for: error)
                    )
                }
                return ViewportMeasurementResolution(
                    endpoint: ViewportMeasurementEndpoint(
                        point: worldPoint,
                        source: .snap(candidate)
                    )
                )
            }

            if let effectivePlane,
               let worldPoint = planarSnapPoint(
                   result: snapResult,
                   plane: effectivePlane
               ),
               worldPoint.isFinite {
                do {
                    try validateWorldPoint(worldPoint)
                } catch {
                    return ViewportMeasurementResolution(
                        endpoint: nil,
                        failure: Self.failure(for: error)
                    )
                }
                return ViewportMeasurementResolution(
                    endpoint: ViewportMeasurementEndpoint(
                        point: worldPoint,
                        source: .snap(candidate)
                    )
                )
            }
        }

        if let presentationHit {
            guard presentationHit.point.isFinite else {
                return ViewportMeasurementResolution(endpoint: nil, failure: .nonFiniteEndpoint)
            }
            return ViewportMeasurementResolution(
                endpoint: ViewportMeasurementEndpoint(
                    point: presentationHit.point,
                    source: .presentation(occurrenceID: presentationHit.occurrenceID)
                )
            )
        }

        guard let effectivePlane else {
            return ViewportMeasurementResolution(
                endpoint: nil,
                failure: .noConstructionPlane
            )
        }
        do {
            let worldPoint = try planeIntersection(effectivePlane)
            guard worldPoint.isFinite else {
                return ViewportMeasurementResolution(endpoint: nil, failure: .nonFiniteEndpoint)
            }
            return ViewportMeasurementResolution(
                endpoint: ViewportMeasurementEndpoint(
                    point: worldPoint,
                    source: .constructionPlane(effectivePlane)
                )
            )
        } catch {
            return ViewportMeasurementResolution(
                endpoint: nil,
                failure: Self.failure(for: error)
            )
        }
    }

    private static func failure(for error: Error) -> ViewportMeasurementResolutionFailure {
        if let failure = error as? ViewportMeasurementResolutionFailure {
            return failure
        }
        return .presentationUnavailable(error.localizedDescription)
    }

    private func planarSnapPoint(
        result: SnapResolutionResult,
        plane: SketchPlane
    ) -> Point3D? {
        do {
            return try SketchPlaneCoordinateSystem(plane: plane).point(from: result.resolvedPoint)
        } catch {
            return nil
        }
    }
}

enum ViewportMeasurementPhase: Equatable, Sendable {
    case idle
    case anchored
    /// Both points are chosen; the cursor chooses the axis and where the dimension line goes.
    case placing
    case completed
}

/// Small value state owned by the mounted Viewport.
public struct ViewportMeasurementState: Equatable, Sendable {
    var phase: ViewportMeasurementPhase
    var start: ViewportMeasurementEndpoint?
    var preview: ViewportMeasurementEndpoint?
    var end: ViewportMeasurementEndpoint?
    public var distanceMeters: Double?
    public var status: String?
    /// The construction-plane axis the dimension measures along, or `nil` for the straight distance.
    public internal(set) var placementAxis: Vector3D?
    /// Where the dimension line passes, once it is being placed.
    public internal(set) var labelPosition: Point3D?
    public internal(set) var boundsSummary: String? = nil
    public var title: String {
        switch phase {
        case .idle: "Measure"
        case .anchored: "Measuring"
        case .placing: "Place Dimension"
        case .completed: "Measured"
        }
    }

    public init() {
        self.phase = .idle
        self.start = nil
        self.preview = nil
        self.end = nil
        self.distanceMeters = nil
        self.status = nil
    }

    init(
        phase: ViewportMeasurementPhase = .idle,
        start: ViewportMeasurementEndpoint? = nil,
        preview: ViewportMeasurementEndpoint? = nil,
        end: ViewportMeasurementEndpoint? = nil,
        distanceMeters: Double? = nil,
        status: String? = nil
    ) {
        self.phase = phase
        self.start = start
        self.preview = preview
        self.end = end
        self.distanceMeters = distanceMeters
        self.status = status
    }

    var visibleEnd: ViewportMeasurementEndpoint? {
        preview ?? end
    }

    /// Whether a completed two-point measurement is available to save.
    public var canSave: Bool {
        phase == .completed && start != nil && end != nil
    }

    /// The persistent start/end anchors of the completed measurement.
    ///
    /// Each endpoint is anchored to the placement it was picked under: a
    /// displayed-surface hit follows its occurrence, a snap follows the one
    /// scene node its sources name, and a construction-plane point stays in
    /// world space. The hierarchy must describe the document the endpoints
    /// were picked in.
    public func savedAnchors(in hierarchy: SceneNodeHierarchy) throws -> [MeasurementAnchor] {
        guard phase == .completed, let start, let end else {
            throw EditorError(code: .commandInvalid, message: "Complete a two-point measurement before saving it.")
        }
        return [
            try start.source.savedAnchor(start.point, role: .start, in: hierarchy),
            try end.source.savedAnchor(end.point, role: .end, in: hierarchy),
        ]
    }

    /// The saved annotation for the completed measurement.
    public func annotation(named name: String, in hierarchy: SceneNodeHierarchy) throws -> MeasurementAnnotation {
        MeasurementAnnotation(
            name: name,
            kind: .distance,
            anchors: try savedAnchors(in: hierarchy),
            labelPosition: labelPosition,
            placementAxis: placementAxis
        )
    }

    /// The dimension being placed or placed, once both points are known.
    public func dimension() throws -> MeasurementDimensionGeometry? {
        guard let start, let end = end ?? preview else { return nil }
        return try MeasurementDimensionGeometry(
            start: start.point, end: end.point, axis: placementAxis, labelPosition: labelPosition
        )
    }
}

extension ViewportMeasurementEndpointSource {
    func pickPlacement(in hierarchy: SceneNodeHierarchy) -> MeasurementPickPlacement {
        switch self {
        case .snap(let candidate):
            candidate.measurementPickPlacement(in: hierarchy)
        case .presentation(let occurrenceID):
            .occurrence(occurrenceID)
        case .constructionPlane, .anchor:
            .world
        }
    }

    /// The anchor a saved measurement keeps for this point: the geometry it was snapped to or
    /// measured on when it has one, else the placement it was picked under.
    func savedAnchor(_ point: Point3D, role: MeasurementAnchor.Role, in hierarchy: SceneNodeHierarchy) throws -> MeasurementAnchor {
        switch self {
        case .anchor(var anchor):
            anchor.role = role
            return anchor
        case .snap(let candidate):
            if let anchor = MeasurementAnchor.associative(for: candidate, role: role) {
                return anchor
            }
        case .presentation, .constructionPlane:
            break
        }
        return try MeasurementAnchor.picked(point, under: pickPlacement(in: hierarchy), in: hierarchy, role: role)
    }
}

struct ViewportMeasurementSession: Equatable, Sendable {
    private(set) var state: ViewportMeasurementState

    init(state: ViewportMeasurementState = ViewportMeasurementState()) {
        self.state = state
    }

    mutating func reset() {
        state = ViewportMeasurementState()
    }

    /// Starts placing a dimension between two known points, such as the ends of a selected edge.
    mutating func measure(from start: ViewportMeasurementEndpoint, to end: ViewportMeasurementEndpoint) {
        state = ViewportMeasurementState(phase: .placing, start: start, end: end)
        state.distanceMeters = Self.distance(from: start.point, to: end.point)
        state.status = Self.placingStatus
    }

    /// Moves the dimension being placed to `cursor`, measuring along `axis` (straight when `nil`).
    mutating func place(cursor: Point3D, axis: Vector3D?) {
        guard state.phase == .placing, let start = state.start, let end = state.end else { return }
        do {
            let dimension = try MeasurementDimensionGeometry(
                start: start.point, end: end.point, axis: axis, labelPosition: cursor
            )
            state.labelPosition = cursor
            state.placementAxis = axis
            state.distanceMeters = dimension.valueMeters
        } catch {
            state.status = error.localizedDescription
        }
    }

    /// Right-click while placing: the straight distance between the two points.
    mutating func confirmStraight() {
        guard state.phase == .placing, let start = state.start, let end = state.end else { return }
        state.placementAxis = nil
        state.distanceMeters = Self.distance(from: start.point, to: end.point)
        complete()
    }

    private mutating func complete() {
        state.phase = .completed
        state.status = "Measured and added to Measurements. Click to start another. Escape clears it."
    }

    private static let placingStatus =
        "Move toward an axis and click to place the dimension. Right-click measures the straight distance."

    mutating func hover(_ endpoint: ViewportMeasurementEndpoint?) {
        guard state.phase == .anchored else {
            return
        }
        state.preview = endpoint
        state.distanceMeters = endpoint.flatMap { endpoint in
            guard let start = state.start else { return nil }
            let distance = Self.distance(from: start.point, to: endpoint.point)
            return distance.isFinite ? distance : nil
        }
        state.status = "Select a second point. Escape cancels."
    }

    mutating func warn(_ message: String?) {
        guard let message else { return }
        state.status = [message, state.status].compactMap { $0 }.joined(separator: " ")
    }

    mutating func refuse(_ failure: ViewportMeasurementResolutionFailure?) {
        guard let failure else { return }
        if state.phase == .anchored {
            state.preview = nil
            state.distanceMeters = nil
        }
        state.status = failure.message
    }

    mutating func click(_ endpoint: ViewportMeasurementEndpoint?) {
        // While placing, a click confirms the dimension wherever it lands.
        if state.phase == .placing {
            complete()
            return
        }
        guard let endpoint else {
            return
        }
        guard endpoint.point.isFinite else {
            refuse(.nonFiniteEndpoint)
            return
        }
        switch state.phase {
        case .placing:
            complete()
        case .idle, .completed:
            state = ViewportMeasurementState(
                phase: .anchored,
                start: endpoint,
                status: "Select a second point."
            )
        case .anchored:
            guard let start = state.start else {
                state = ViewportMeasurementState()
                return
            }
            let distance = Self.distance(from: start.point, to: endpoint.point)
            guard distance.isFinite, distance > 1.0e-12 else {
                state.preview = nil
                state.distanceMeters = nil
                state.status = "Measurement endpoints must not be identical."
                return
            }
            state.preview = nil
            state.end = endpoint
            state.distanceMeters = distance
            state.phase = .placing
            state.status = Self.placingStatus
        }
    }

    private static func distance(from first: Point3D, to second: Point3D) -> Double {
        let dx = second.x - first.x
        let dy = second.y - first.y
        let dz = second.z - first.z
        return hypot(hypot(dx, dy), dz)
    }
}

enum ViewportMeasurementRulerAxis: String, CaseIterable, Equatable, Hashable, Sendable {
    case x
    case y
    case z

    var title: String { rawValue.uppercased() }
}

/// Axis labels retained by a prepared selected-bounds ruler group.  The
/// strings are formatted once when the source/measurement revision changes;
/// camera-only updates never format them again.
struct ViewportMeasurementBoundsRulerLabels: Equatable, Sendable {
    let x: String?
    let y: String?
    let z: String?

    init(x: String? = nil, y: String? = nil, z: String? = nil) {
        self.x = x
        self.y = y
        self.z = z
    }

    subscript(axis: ViewportMeasurementRulerAxis) -> String? {
        switch axis {
        case .x: x
        case .y: y
        case .z: z
        }
    }
}

/// Immutable selected-bounds input for the native camera-relative ruler
/// group.  It intentionally contains no projection or screen placement.
struct ViewportMeasurementBoundsRulerInput: Equatable, Sendable {
    let bounds: GeometryBounds3D
    let labels: ViewportMeasurementBoundsRulerLabels

    init(bounds: GeometryBounds3D, labels: ViewportMeasurementBoundsRulerLabels) {
        self.bounds = bounds
        self.labels = labels
    }
}

struct ViewportMeasurementBoundsRuler: Equatable {
    let axis: ViewportMeasurementRulerAxis
    /// The unprojected world edge represented by the ruler.  The existing
    /// projected fields remain the bounded collision-placement result for the
    /// legacy Canvas route; native RealityKit uses these world values and the
    /// camera-relative offset instead of baking a screen point into geometry.
    let worldExtensionStart: Point3D
    let worldExtensionEnd: Point3D
    let dimensionOffset: CGPoint
    let extensionStart: CGPoint
    let extensionEnd: CGPoint
    let dimensionStart: CGPoint
    let dimensionEnd: CGPoint
    let label: String
    let labelRect: CGRect
    let valueMeters: Double

    init(
        axis: ViewportMeasurementRulerAxis,
        worldExtensionStart: Point3D,
        worldExtensionEnd: Point3D,
        dimensionOffset: CGPoint,
        extensionStart: CGPoint,
        extensionEnd: CGPoint,
        dimensionStart: CGPoint,
        dimensionEnd: CGPoint,
        label: String,
        labelRect: CGRect,
        valueMeters: Double
    ) {
        self.axis = axis
        self.worldExtensionStart = worldExtensionStart
        self.worldExtensionEnd = worldExtensionEnd
        self.dimensionOffset = dimensionOffset
        self.extensionStart = extensionStart
        self.extensionEnd = extensionEnd
        self.dimensionStart = dimensionStart
        self.dimensionEnd = dimensionEnd
        self.label = label
        self.labelRect = labelRect
        self.valueMeters = valueMeters
    }
}

/// Result of one bounded selected-bounds placement pass.  Axes without a
/// finite extent, a usable label, or a collision-free candidate are returned
/// explicitly in `disabledAxes`; they are never silently truncated.
struct ViewportMeasurementBoundsRulerPlacement: Equatable {
    let rulers: [ViewportMeasurementBoundsRuler]
    let disabledAxes: Set<ViewportMeasurementRulerAxis>
}

/// Constant-work placement for one selected occurrence's three world extents.
struct ViewportMeasurementBoundsRulerLayout: Sendable {
    private struct ProjectedBounds {
        let points: [Point3D]
        let projected: [CGPoint]
        let objectRect: CGRect
    }

    init() {}

    /// Produces the immutable labels retained by a prepared native ruler
    /// group.  Projection and collision placement are deliberately absent.
    func preformattedLabels(
        for bounds: GeometryBounds3D,
        displayUnit: LengthDisplayUnit
    ) -> ViewportMeasurementBoundsRulerLabels {
        let minimumExtent = 1.0e-12
        func label(
            axis: ViewportMeasurementRulerAxis,
            value: Double
        ) -> String? {
            guard value.isFinite, value > minimumExtent else { return nil }
            return "World bounds \(axis.title): \(ViewportLengthLabelFormatter.string(fromMeters: value, preferredUnit: displayUnit))"
        }
        return ViewportMeasurementBoundsRulerLabels(
            x: label(axis: .x, value: bounds.maximum.x - bounds.minimum.x),
            y: label(axis: .y, value: bounds.maximum.y - bounds.minimum.y),
            z: label(axis: .z, value: bounds.maximum.z - bounds.minimum.z)
        )
    }

    /// Recomputes only bounded ruler placement from immutable world bounds,
    /// retained labels, the current native projection, and current chrome
    /// exclusions.  The closure is synchronous and is called only for the
    /// fixed eight bounds corners plus the fixed four candidates per axis.
    func placement(
        for bounds: GeometryBounds3D,
        labels: ViewportMeasurementBoundsRulerLabels,
        project: (Point3D) -> CGPoint?,
        safeRect: CGRect,
        excludedRects: [CGRect]
    ) -> ViewportMeasurementBoundsRulerPlacement {
        let allAxes = Set(ViewportMeasurementRulerAxis.allCases)
        guard bounds.minimum.x.isFinite, bounds.minimum.y.isFinite,
              bounds.minimum.z.isFinite, bounds.maximum.x.isFinite,
              bounds.maximum.y.isFinite, bounds.maximum.z.isFinite,
              bounds.maximum.x >= bounds.minimum.x,
              bounds.maximum.y >= bounds.minimum.y,
              bounds.maximum.z >= bounds.minimum.z,
              safeRect.hasFiniteComponents else {
            return ViewportMeasurementBoundsRulerPlacement(
                rulers: [], disabledAxes: allAxes
            )
        }
        guard let projectedBounds = projectBounds(bounds, project: project) else {
            return ViewportMeasurementBoundsRulerPlacement(
                rulers: [], disabledAxes: allAxes
            )
        }

        let minimumExtent = 1.0e-12
        let extents: [(ViewportMeasurementRulerAxis, Double)] = [
            (.x, bounds.maximum.x - bounds.minimum.x),
            (.y, bounds.maximum.y - bounds.minimum.y),
            (.z, bounds.maximum.z - bounds.minimum.z),
        ]
        var acceptedLabels: [CGRect] = []
        var acceptedLines: [(CGPoint, CGPoint)] = []
        var result: [ViewportMeasurementBoundsRuler] = []
        var disabledAxes: Set<ViewportMeasurementRulerAxis> = []

        func crosses(_ lines: [(CGPoint, CGPoint)], _ rect: CGRect) -> Bool {
            lines.contains {
                ViewportMeasurementRulerCollision.segmentIntersects($0.0, $0.1, rect: rect)
            }
        }

        for (axis, value) in extents {
            guard value.isFinite, value > minimumExtent,
                  let label = labels[axis], !label.isEmpty else {
                disabledAxes.insert(axis)
                continue
            }
            var accepted = false
            for (start, end) in edgeCandidates(for: axis, bounds: bounds) {
                guard let projectedStart = project(start),
                      let projectedEnd = project(end),
                      projectedStart.x.isFinite, projectedStart.y.isFinite,
                      projectedEnd.x.isFinite, projectedEnd.y.isFinite else {
                    continue
                }
                let dx = projectedEnd.x - projectedStart.x
                let dy = projectedEnd.y - projectedStart.y
                let length = hypot(dx, dy)
                guard length > 1.0e-6 else { continue }
                var normal = CGPoint(x: -dy / length, y: dx / length)
                let midpoint = CGPoint(
                    x: (projectedStart.x + projectedEnd.x) * 0.5,
                    y: (projectedStart.y + projectedEnd.y) * 0.5
                )
                let objectCenter = CGPoint(
                    x: projectedBounds.objectRect.midX,
                    y: projectedBounds.objectRect.midY
                )
                let away = CGPoint(
                    x: midpoint.x - objectCenter.x,
                    y: midpoint.y - objectCenter.y
                )
                if away.x * normal.x + away.y * normal.y < 0.0 {
                    normal.x *= -1.0
                    normal.y *= -1.0
                }
                let rect = projectedBounds.objectRect.insetBy(dx: -16, dy: -16)
                var offset = CGFloat.infinity
                if normal.x > 1.0e-6 {
                    offset = min(offset, (rect.maxX - min(projectedStart.x, projectedEnd.x)) / normal.x)
                } else if normal.x < -1.0e-6 {
                    offset = min(offset, (rect.minX - max(projectedStart.x, projectedEnd.x)) / normal.x)
                }
                if normal.y > 1.0e-6 {
                    offset = min(offset, (rect.maxY - min(projectedStart.y, projectedEnd.y)) / normal.y)
                } else if normal.y < -1.0e-6 {
                    offset = min(offset, (rect.minY - max(projectedStart.y, projectedEnd.y)) / normal.y)
                }
                guard offset.isFinite else { continue }
                offset = max(16, offset)
                let dimensionStart = CGPoint(
                    x: projectedStart.x + normal.x * offset,
                    y: projectedStart.y + normal.y * offset
                )
                let dimensionEnd = CGPoint(
                    x: projectedEnd.x + normal.x * offset,
                    y: projectedEnd.y + normal.y * offset
                )
                let labelSize = CGSize(
                    width: max(52.0, CGFloat(label.count) * 6.4 + 14.0),
                    height: 20.0
                )
                let labelCenter = CGPoint(
                    x: (dimensionStart.x + dimensionEnd.x) * 0.5 + normal.x * 12.0,
                    y: (dimensionStart.y + dimensionEnd.y) * 0.5 + normal.y * 12.0
                )
                let labelRect = CGRect(
                    x: labelCenter.x - labelSize.width * 0.5,
                    y: labelCenter.y - labelSize.height * 0.5,
                    width: labelSize.width,
                    height: labelSize.height
                )
                let dimensionRect = CGRect(
                    x: min(dimensionStart.x, dimensionEnd.x) - 2.0,
                    y: min(dimensionStart.y, dimensionEnd.y) - 2.0,
                    width: abs(dimensionEnd.x - dimensionStart.x) + 4.0,
                    height: abs(dimensionEnd.y - dimensionStart.y) + 4.0
                )
                let lines = [
                    (projectedStart, dimensionStart),
                    (projectedEnd, dimensionEnd),
                    (dimensionStart, dimensionEnd),
                ]
                let objectInterior = projectedBounds.objectRect.insetBy(dx: 1, dy: 1)
                guard safeRect.contains(labelRect), safeRect.contains(dimensionRect),
                      !projectedBounds.objectRect.intersects(labelRect),
                      !projectedBounds.objectRect.intersects(dimensionRect),
                      !crosses(lines, objectInterior),
                      excludedRects.allSatisfy({ !$0.intersects(labelRect) && !$0.intersects(dimensionRect) }),
                      excludedRects.allSatisfy({ !crosses(lines, $0.insetBy(dx: -1, dy: -1)) }),
                      !crosses(acceptedLines, labelRect.insetBy(dx: -1, dy: -1)),
                      acceptedLabels.allSatisfy({ !$0.intersects(labelRect)
                          && !crosses(lines, $0.insetBy(dx: -1, dy: -1)) }) else {
                    continue
                }
                acceptedLabels.append(labelRect)
                acceptedLines.append(contentsOf: lines)
                result.append(ViewportMeasurementBoundsRuler(
                    axis: axis,
                    worldExtensionStart: start,
                    worldExtensionEnd: end,
                    dimensionOffset: CGPoint(
                        x: normal.x * offset,
                        y: normal.y * offset
                    ),
                    extensionStart: projectedStart,
                    extensionEnd: projectedEnd,
                    dimensionStart: dimensionStart,
                    dimensionEnd: dimensionEnd,
                    label: label,
                    labelRect: labelRect,
                    valueMeters: value
                ))
                accepted = true
                break
            }
            if !accepted {
                disabledAxes.insert(axis)
            }
        }
        return ViewportMeasurementBoundsRulerPlacement(
            rulers: result,
            disabledAxes: disabledAxes
        )
    }

    private func projectBounds(
        _ bounds: GeometryBounds3D,
        project: (Point3D) -> CGPoint?
    ) -> ProjectedBounds? {
        let points = corners(of: bounds)
        let projected = points.compactMap(project)
        guard projected.count == points.count,
              projected.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }
        var objectRect = CGRect.null
        for point in projected {
            objectRect = objectRect.union(CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0))
        }
        guard !objectRect.isNull, objectRect.hasFiniteComponents else { return nil }
        return ProjectedBounds(points: points, projected: projected, objectRect: objectRect)
    }

    private func corners(of bounds: GeometryBounds3D) -> [Point3D] {
        [
            Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z),
            Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.maximum.z),
            Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.minimum.z),
            Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.maximum.z),
            Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.minimum.z),
            Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.maximum.z),
            Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.minimum.z),
            Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z),
        ]
    }

    private func edgeCandidates(
        for axis: ViewportMeasurementRulerAxis,
        bounds: GeometryBounds3D
    ) -> [(Point3D, Point3D)] {
        switch axis {
        case .x:
            return [
                (Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z), Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.minimum.z)),
                (Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.maximum.z), Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.maximum.z)),
                (Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.minimum.z), Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.minimum.z)),
                (Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.maximum.z), Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z)),
            ]
        case .y:
            return [
                (Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z), Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.minimum.z)),
                (Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.maximum.z), Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.maximum.z)),
                (Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.minimum.z), Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.minimum.z)),
                (Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.maximum.z), Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z)),
            ]
        case .z:
            return [
                (Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.minimum.z), Point3D(x: bounds.minimum.x, y: bounds.minimum.y, z: bounds.maximum.z)),
                (Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.minimum.z), Point3D(x: bounds.minimum.x, y: bounds.maximum.y, z: bounds.maximum.z)),
                (Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.minimum.z), Point3D(x: bounds.maximum.x, y: bounds.minimum.y, z: bounds.maximum.z)),
                (Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.minimum.z), Point3D(x: bounds.maximum.x, y: bounds.maximum.y, z: bounds.maximum.z)),
            ]
        }
    }
}
