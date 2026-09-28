import Foundation
import SwiftCAD
import RupaCoreTypes

/// A projected outline curve by the points that identify it on its plane, for telling two
/// outline pieces apart: a line by its ends, a circle by its center and one rim point, an arc by
/// its ends and its middle (so the two halves of one circle differ), a spline by its degree,
/// knots and control points. Two curves are the same when their points agree within the
/// tolerance in the same order or reversed (a curve drawn the other way round).
struct OutlineCurveIdentity: Equatable {
    var kind: String
    var knots: [Double]?
    var points: [Point2D]

    func matches(_ other: OutlineCurveIdentity, tolerance: Double) -> Bool {
        guard kind == other.kind, knots == other.knots, points.count == other.points.count else { return false }
        func agree(_ a: [Point2D], _ b: [Point2D]) -> Bool {
            zip(a, b).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) <= tolerance }
        }
        // A curve drawn the other way round is the same curve; explicit knots keep their order.
        return agree(points, other.points) || (knots == nil && agree(points, other.points.reversed()))
    }
}

extension DesignDocument {
    func outlineCurveIdentity(_ entity: SketchEntity) throws -> OutlineCurveIdentity {
        let owner = "Projected outline"
        func point(_ sketchPoint: SketchPoint) throws -> Point2D {
            let resolved = try resolvedProjectionPoint(sketchPoint, owner: owner)
            return Point2D(x: resolved.x, y: resolved.y)
        }
        switch entity {
        case .line(let line):
            return OutlineCurveIdentity(kind: "line", knots: nil, points: [try point(line.start), try point(line.end)])
        case .circle(let circle):
            let center = try point(circle.center)
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
            // A circle has no direction; its center and radius name it.
            return OutlineCurveIdentity(kind: "circle", knots: nil, points: [center, Point2D(x: center.x + radius, y: center.y)])
        case .arc(let arc):
            let center = try point(arc.center)
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
            let span = positiveArcSpan(startAngle: startAngle, endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle"))
            let points = [startAngle, startAngle + span / 2, startAngle + span].map {
                Point2D(x: center.x + cos($0) * radius, y: center.y + sin($0) * radius)
            }
            return OutlineCurveIdentity(kind: "arc", knots: nil, points: points)
        case .spline(let spline):
            return OutlineCurveIdentity(kind: "spline\(spline.degree)", knots: spline.knots, points: try spline.controlPoints.map(point))
        case .point:
            throw EditorError(code: .commandInvalid, message: "\(owner) takes curves, not points.")
        }
    }
}
