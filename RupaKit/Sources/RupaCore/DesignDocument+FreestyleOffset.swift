import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Freestyle Offset Planar Curve: the signed distance `offsetCurve` takes to put the offset of
    /// the selected curve through `worldPoint`, read on the curve's sketch plane (through its
    /// scene placement) from the nearest point of the curve. The sign follows `offsetCurve`: a
    /// line, a spline and a joined chain (in the chain's own direction) are positive on their
    /// left, an arc or circle outside its circle.
    public func freestyleOffsetDistance(target: SelectionTarget, through worldPoint: Point3D) throws -> Double {
        let owner = "Freestyle Offset"
        let selection = try editableSketchEntity(for: target, operationName: owner)
        // Into the sketch's own orthonormal coordinates, where offset distances are measured.
        let local = try SketchPlaneCoordinateSystem(plane: selection.sketch.plane)
            .project(try worldPlacement(of: target.sceneNodeID).inverse().applied(to: worldPoint)).point
        if let group = joinedCurveGroup(featureID: selection.featureID, entityID: selection.entityID) {
            return try Self.signedLeftDistance(from: local, toSpans: try joinedChainSpans(group, sketch: selection.sketch))
        }
        switch selection.entity {
        case .line, .spline:
            return try Self.signedLeftDistance(from: local, toSpans: try bezierSpans(of: selection.entity, owner: owner))
        case .arc(let arc):
            let center = try resolvedProjectionPoint(arc.center, owner: "\(owner) arc center")
            return hypot(local.x - center.x, local.y - center.y) - (try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius"))
        case .circle(let circle):
            let center = try resolvedProjectionPoint(circle.center, owner: "\(owner) circle center")
            return hypot(local.x - center.x, local.y - center.y) - (try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius"))
        case .point:
            throw EditorError(code: .commandInvalid, message: "\(owner) offsets curves, not points.")
        }
    }

    /// The distance from `point` to the nearest point of the Bezier spans, positive when the
    /// point is on the spans' left there. Each span is sampled and the best sample refined by
    /// golden-section search.
    static func signedLeftDistance(from point: Point2D, toSpans spans: [[Point2D]]) throws -> Double {
        func distance(_ span: [Point2D], _ t: Double) -> Double {
            let p = bezierJet(span, t).point
            return hypot(p.x - point.x, p.y - point.y)
        }
        let samples = 64
        let ratio = (5.0.squareRoot() - 1) / 2
        var best: (distance: Double, span: Int, t: Double) = (.infinity, 0, 0)
        for (index, span) in spans.enumerated() {
            let distances = (0...samples).map { distance(span, Double($0) / Double(samples)) }
            guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }) else { continue }
            // Golden-section search between the nearest sample's neighbours.
            var a = Double(max(0, nearest - 1)) / Double(samples), b = Double(min(samples, nearest + 1)) / Double(samples)
            for _ in 0..<80 {
                let c = b - ratio * (b - a), d = a + ratio * (b - a)
                if distance(span, c) < distance(span, d) { b = d } else { a = c }
            }
            let t = (a + b) / 2
            if distance(span, t) < best.distance { best = (distance(span, t), index, t) }
        }
        guard best.distance.isFinite else {
            throw EditorError(code: .commandInvalid, message: "Freestyle Offset found no curve to measure from.")
        }
        let jet = bezierJet(spans[best.span], best.t)
        let side = jet.derivative.x * (point.y - jet.point.y) - jet.derivative.y * (point.x - jet.point.x)
        return side >= 0 ? best.distance : -best.distance
    }

    /// A Bezier span's point and first derivative at `t`, by de Casteljau.
    static func bezierJet(_ span: [Point2D], _ t: Double) -> (point: Point2D, derivative: Point2D) {
        func casteljau(_ points: [Point2D]) -> Point2D {
            var q = points
            while q.count > 1 {
                q = zip(q, q.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }
            }
            return q[0]
        }
        let degree = Double(span.count - 1)
        let differences = zip(span, span.dropFirst()).map { Point2D(x: ($1.x - $0.x) * degree, y: ($1.y - $0.y) * degree) }
        return (casteljau(span), differences.isEmpty ? Point2D(x: 0, y: 0) : casteljau(differences))
    }
}
