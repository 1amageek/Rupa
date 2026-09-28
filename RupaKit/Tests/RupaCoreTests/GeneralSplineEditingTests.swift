import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Editing commands on a spline of any degree or knots either work on its own curve (split,
/// trim, cut, Natural extension) or refuse it by name (commands that still read cubic spans),
/// never reading it as the cubic chain its control point count might make.
@MainActor
@Suite struct GeneralSplineEditingTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    /// A quintic of two spans (11 points, joint at index 5).
    private func quintic() -> SketchSpline {
        SketchSpline(
            controlPoints: [(0, 0), (2, 4), (4, -2), (6, 5), (8, -1), (10, 2), (12, 5), (14, -3), (16, 4), (18, 0), (20, 2)]
                .map { point($0.0, $0.1) },
            degree: 5
        )
    }

    /// A sextic of one span: seven points, which a count-only reader would take for a cubic chain.
    private func sextic() -> SketchSpline {
        SketchSpline(controlPoints: [(0, 0), (2, 3), (4, -1), (6, 4), (8, 0), (10, 3), (12, 1)].map { point($0.0, $0.1) }, degree: 6)
    }

    private func document(_ spline: SketchSpline) throws -> (DesignDocument, FeatureID, SketchEntityID) {
        var document = DesignDocument.empty()
        let featureID = try document.createSplineSketch(name: "General", plane: .xy, spline: spline)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first else {
            throw EditorError(code: .referenceUnresolved, message: "The spline sketch is missing.")
        }
        return (document, featureID, entityID)
    }

    private func sketch(_ document: DesignDocument, _ featureID: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return sketch
    }

    private func target(_ document: DesignDocument, _ featureID: FeatureID, _ component: SelectionComponentID) throws -> SelectionTarget {
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { _, node in
            node.reference?.kind == .sketch && node.reference?.featureID == featureID
        }?.key)
        return SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(component))
    }

    /// Dense points of `spline` in millimeters, over its whole knot domain.
    private func dense(_ document: DesignDocument, _ spline: SketchSpline, count: Int = 400) throws -> [Point2D] {
        let curve = try document.resolvedSketchSplineCurve(spline, owner: "Test")
        let (lower, upper) = curve.domain
        return try (0...count).map {
            let p = try curve.bSpline.point(at: lower + (upper - lower) * Double($0) / Double(count), tolerance: .standard)
            return Point2D(x: p.x * 1000, y: p.y * 1000)
        }
    }

    private func distance(from p: Point2D, to points: [Point2D]) -> Double {
        points.map { hypot($0.x - p.x, $0.y - p.y) }.min() ?? .infinity
    }

    @Test func splittingASexticKeepsItsCurveAndItsDegree() throws {
        var (document, featureID, entityID) = try document(sextic())
        let original = try dense(document, sextic(), count: 4000)
        let newID = try document.splitSketchCurve(
            target: target(document, featureID, .sketchEntity(featureID: featureID, entityID: entityID)),
            fraction: .scalar(0.3)
        )
        let result = try sketch(document, featureID)
        guard case .spline(let retained) = result.entities[entityID], case .spline(let next) = result.entities[newID] else {
            Issue.record("Both parts must be splines.")
            return
        }
        #expect(retained.degree == 6 && next.degree == 6)
        for part in [retained, next] {
            for p in try dense(document, part) {
                #expect(distance(from: p, to: original) <= 1e-3)
            }
        }
        #expect(try dense(document, retained).last.map { hypot($0.x - (try dense(document, next).first!.x), $0.y - (try dense(document, next).first!.y)) }! <= 1e-9)
    }

    @Test func splittingAGeneralSplineRefusesConstraintsOnItsInterior() throws {
        var (document, featureID, entityID) = try document(sextic())
        try document.addSketchConstraint(featureID: featureID, constraint: .fixed(.splineControlPoint(entity: entityID, index: 2)))
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.splitSketchCurve(
                target: target(document, featureID, .sketchEntity(featureID: featureID, entityID: entityID)),
                fraction: .scalar(0.5)
            )
        }
        #expect(document.cadDocument.designGraph == before)
    }

    /// Trim on a quintic of two spans removes the span under the click, bounded by its joint.
    @Test func trimmingAQuinticStopsAtItsJoint() throws {
        var (document, featureID, entityID) = try document(quintic())
        let original = try dense(document, quintic(), count: 4000)
        try document.trimSketchCurve(
            target: target(document, featureID, .sketchEntity(featureID: featureID, entityID: entityID)),
            near: Point2D(x: 0.015, y: 0.001)
        )
        let splines = try sketch(document, featureID).entities.values.compactMap { entity -> SketchSpline? in
            if case .spline(let spline) = entity { return spline }
            return nil
        }
        #expect(splines.count == 1)
        let kept = try #require(splines.first)
        let keptPoints = try dense(document, kept)
        // What is left is the first span, ending at the joint (10, 2).
        #expect(hypot(keptPoints.last!.x - 10, keptPoints.last!.y - 2) <= 1e-9)
        for p in keptPoints {
            #expect(distance(from: p, to: original) <= 1e-3)
        }
    }

    /// A quintic's Natural extension continues its last segment's own polynomial.
    @Test func extendingAQuinticContinuesItsOwnPolynomial() throws {
        var (document, featureID, entityID) = try document(quintic())
        try document.extendSketchCurve(
            target: target(document, featureID, .sketchControlPoint(featureID: featureID, entityID: entityID, index: 10)),
            distance: mm(3),
            shape: .natural
        )
        guard case .spline(let extended) = try sketch(document, featureID).entities[entityID] else {
            Issue.record("The spline must remain.")
            return
        }
        #expect(extended.degree == 5 && extended.controlPoints.count == 16)
        let curve = try document.resolvedSketchSplineCurve(extended, owner: "Test")
        let last = try #require(curve.segments.last), before = curve.segments[curve.segments.count - 2]
        // The new segment is the previous segment's polynomial on [1, s]: its first derivative at
        // the joint points along the previous one's.
        let d0 = Point2D(x: last.controlPoints[1].x - last.controlPoints[0].x, y: last.controlPoints[1].y - last.controlPoints[0].y)
        let d1 = Point2D(x: before.controlPoints[5].x - before.controlPoints[4].x, y: before.controlPoints[5].y - before.controlPoints[4].y)
        #expect(abs(d0.x * d1.y - d0.y * d1.x) <= 1e-12 * hypot(d0.x, d0.y) * hypot(d1.x, d1.y) + 1e-18)
        #expect(d0.x * d1.x + d0.y * d1.y > 0)
    }

    @Test func commandsThatReadCubicSpansRefuseASexticByName() throws {
        var (document, featureID, entityID) = try document(sextic())
        let entity = try target(document, featureID, .sketchEntity(featureID: featureID, entityID: entityID))
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) { try document.deleteRedundantSketchSplineJoints(target: entity) }
        #expect(throws: EditorError.self) {
            _ = try document.rebuildSketchCurve(target: entity, options: CurveRebuildOptions(method: .points(controlPointCount: 7)))
        }
        #expect(document.cadDocument.designGraph == before)
    }
}
