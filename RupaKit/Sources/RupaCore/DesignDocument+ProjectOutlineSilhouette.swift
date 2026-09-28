import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Project Outline keeps an edge, or the part of it, whose projection bounds the body's
    /// shadow on the plane: beside it the body covers the plane on one side only. Edges inside
    /// the shadow (covered on both sides) and edges seen end-on are left out.
    ///
    /// Each edge is read at `outlineSampleCount` parameters, each a small step to either side of
    /// its projection is lifted onto a line along the plane's normal, and the line meets the body
    /// when it meets one of its faces inside the trim (Swift-CAD's directional projection). A
    /// change between outline and interior along the edge is found by bisection.
    func outlineSketchEntities(
        edge: ResolvedEdge,
        faces: [SurfaceReference],
        placement: Transform3D,
        in evaluated: EvaluatedDocument,
        system: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> [SketchEntity] {
        try outlinePieces(edge: edge, faces: faces, placement: placement, in: evaluated, system: system).compactMap { piece in
            try outlinePieceEntity(edge: edge, from: piece.lower, to: piece.upper, placement: placement, system: system)
        }
    }

    /// The parameter ranges of `edge` that bound the body's shadow on the plane of `system` (in
    /// world space); the edge and faces are in the body's source frame, placed by `placement`.
    func outlinePieces(
        edge: ResolvedEdge,
        faces: [SurfaceReference],
        placement: Transform3D,
        in evaluated: EvaluatedDocument,
        system: SketchPlaneCoordinateSystem
    ) throws -> [(lower: Double, upper: Double)] {
        let inverse = try placement.inverse()
        let bodyNormal = try inverse.applyingLinearPart(to: system.normal).normalized(tolerance: 1.0e-12)
        let tolerance = modelingSettings.tolerance
        let evaluator = SurfaceQueryEvaluator(tolerance: tolerance)
        let lower = edge.startParameter, upper = edge.endParameter
        guard upper > lower else { return [] }
        let step = tolerance.distance * Self.outlineSideStepFactor

        func projected(_ t: Double) throws -> (point: Point2D, tangent: Point2D) {
            let geometry = try edge.curve.differentialGeometry(at: t, tolerance: tolerance)
            let d = try placement.applyingLinearPart(to: geometry.firstDerivative)
            return (system.project(try placement.applied(to: geometry.position)).point, Point2D(x: d.dot(system.u), y: d.dot(system.v)))
        }
        func covers(_ point: Point2D) throws -> Bool {
            let origin = try inverse.applied(to: system.point(from: point))
            for face in faces {
                do {
                    _ = try evaluator.project(origin, along: bodyNormal, onto: face, in: evaluated,
                                              options: SurfaceDirectionalProjectionOptions(range: .line))
                    return true
                } catch FeatureEvaluationError.emptyResult {
                    // The line misses this face; another may cover the point.
                    continue
                }
            }
            return false
        }
        /// Whether the edge bounds the shadow at `t`; an edge seen end-on there does not.
        func isOutline(_ t: Double) throws -> Bool {
            let (point, tangent) = try projected(t)
            let length = hypot(tangent.x, tangent.y)
            guard length > 1.0e-12 else { return false }
            let side = Point2D(x: -tangent.y / length * step, y: tangent.x / length * step)
            let left = try covers(Point2D(x: point.x + side.x, y: point.y + side.y))
            let right = try covers(Point2D(x: point.x - side.x, y: point.y - side.y))
            return left != right
        }

        // Interior samples only: at a vertex both sides can meet other faces' corners.
        let samples = (0..<Self.outlineSampleCount).map { lower + (upper - lower) * (Double($0) + 0.5) / Double(Self.outlineSampleCount) }
        let states = try samples.map(isOutline)
        var pieces: [(Double, Double)] = []
        var pieceStart: Double? = states[0] ? lower : nil
        for index in 1..<samples.count where states[index] != states[index - 1] {
            // Bisect the change between the two samples.
            var a = samples[index - 1], b = samples[index]
            for _ in 0..<Self.outlineBisectionCount {
                let middle = (a + b) / 2
                if try isOutline(middle) == states[index - 1] { a = middle } else { b = middle }
            }
            let change = (a + b) / 2
            if states[index] {
                pieceStart = change
            } else if let start = pieceStart {
                pieces.append((start, change))
                pieceStart = nil
            }
        }
        if let start = pieceStart { pieces.append((start, upper)) }
        return pieces.map { (lower: $0.0, upper: $0.1) }
    }

    /// Sample count along each edge for the outline test.
    static let outlineSampleCount = 8
    /// Bisection steps locating where an edge leaves or joins the outline.
    static let outlineBisectionCount = 24
    /// The step to either side of an edge's projection, in modeling distances.
    static let outlineSideStepFactor = 20.0

    /// One outline piece as a sketch curve on the plane: a line stays a line, a circle parallel
    /// to the plane an arc (a circle when the piece is the whole of a closed edge), and any
    /// other curve a cubic chain fitted within ten modeling distances.
    private func outlinePieceEntity(
        edge: ResolvedEdge, from a: Double, to b: Double, placement: Transform3D, system: SketchPlaneCoordinateSystem
    ) throws -> SketchEntity? {
        let tolerance = modelingSettings.tolerance
        func world(_ t: Double) throws -> Point3D { try placement.applied(to: try edge.curve.point(at: t, tolerance: tolerance)) }
        let start = system.project(try world(a)).point
        let end = system.project(try world(b)).point
        // A circle stays a circle only through a rigid placement.
        let isRigid: Bool
        do {
            _ = try placement.rigidPlacement(tolerance: tolerance)
            isRigid = true
        } catch {
            isRigid = false
        }
        let isWholeClosedEdge = a == edge.startParameter && b == edge.endParameter
            && (edge.startPoint - edge.endPoint).length <= tolerance.distance
        var isParallelCircle = false
        if case .circle(let circle) = edge.curve, isRigid {
            let normal = try placement.applyingLinearPart(to: circle.normal).normalized(tolerance: 1.0e-15)
            isParallelCircle = abs(abs(normal.dot(system.normal)) - 1) <= tolerance.angle
        }
        switch edge.curve {
        case .line:
            guard hypot(end.x - start.x, end.y - start.y) > tolerance.distance else { return nil }
            return .line(SketchLine(start: sketchPoint(from: start), end: sketchPoint(from: end)))
        case .circle(let circle) where isParallelCircle:
            let center = system.project(try placement.applied(to: circle.center)).point
            if isWholeClosedEdge {
                return .circle(SketchCircle(center: sketchPoint(from: center), radius: .length(circle.radius, .meter)))
            }
            // A sketch arc runs counterclockwise: the piece's own sense decides which end starts.
            let tangent = try placement.applyingLinearPart(to: edge.curve.differentialGeometry(at: a, tolerance: tolerance).firstDerivative)
            let sense = (start.x - center.x) * tangent.dot(system.v) - (start.y - center.y) * tangent.dot(system.u)
            let startAngle = atan2(start.y - center.y, start.x - center.x)
            let endAngle = atan2(end.y - center.y, end.x - center.x)
            return .arc(SketchArc(
                center: sketchPoint(from: center),
                radius: .length(circle.radius, .meter),
                startAngle: .angle(sense > 0 ? startAngle : endAngle, .radian),
                endAngle: .angle(sense > 0 ? endAngle : startAngle, .radian)
            ))
        default:
            let fitted = try SpatialCurveFitter(deviation: tolerance.distance * Self.spatialFitDeviationFactor).fit(
                breakpoints: [a, b], isClosed: isWholeClosedEdge, tolerance: tolerance
            ) { t in
                system.point(from: system.project(try world(t)).point)
            }
            // The fitted path lies in the plane: its Bezier control points are the chain's.
            var points: [Point2D] = []
            let knots = fitted.path.knots
            for index in 0..<fitted.path.segmentCount {
                let knot = knots[index], next = knots[(index + 1) % knots.count]
                if index == 0 { points.append(system.project(knot.position).point) }
                points.append(system.project(knot.position + knot.outgoing).point)
                points.append(system.project(next.position + next.incoming).point)
                points.append(system.project(next.position).point)
            }
            // A closed chain's last control point is its first, which the wrap appended.
            return .spline(SketchSpline(controlPoints: points.map(sketchPoint(from:)), isClosed: isWholeClosedEdge))
        }
    }
}
