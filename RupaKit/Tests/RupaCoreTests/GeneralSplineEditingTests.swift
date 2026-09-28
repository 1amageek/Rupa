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

    /// Rebuild's Points refits a sextic as a cubic with the asked number of points, any count.
    @Test func rebuildingASexticByPointsRefitsItAsACubic() throws {
        var (document, featureID, entityID) = try document(sextic())
        let original = try dense(document, sextic(), count: 4000)
        let report = try document.rebuildSketchCurve(
            target: target(document, featureID, .sketchEntity(featureID: featureID, entityID: entityID)),
            options: .points(controlPointCount: 9)
        )
        #expect(report.deviationMeasurement == .sampledProjection)
        #expect(report.rebuiltControlPointCount == 9)
        guard case .spline(let rebuilt) = try sketch(document, featureID).entities[entityID] else { return }
        #expect(rebuilt.degree == 3 && rebuilt.controlPoints.count == 9)
        for p in try dense(document, rebuilt) {
            #expect(distance(from: p, to: original) <= max(report.maximumDeviationMeters * 1000, 1e-3) + 1e-3)
        }
        #expect(report.maximumDeviationMeters < 1e-4)
    }

    @Test func commandsThatReadCubicSpansRefuseASexticByName() throws {
        var (document, featureID, entityID) = try document(sextic())
        let entity = try target(document, featureID, .sketchEntity(featureID: featureID, entityID: entityID))
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) { try document.deleteRedundantSketchSplineJoints(target: entity) }
        #expect(document.cadDocument.designGraph == before)
    }
}

/// Extend Curve's Soft, Arc and Reflective shapes on a spline end.
@MainActor
@Suite struct SplineProfileExtensionTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private let spline = SketchSpline(controlPoints: [(0.0, 0.0), (3.0, 4.0), (7.0, 5.0), (10.0, 3.0)].map { (x: Double, y: Double) in
        SketchPoint(x: .length(x, .millimeter), y: .length(y, .millimeter))
    })

    private func extended(_ shape: ExtendCurveShape, atStart: Bool = false, length: Double = 4) throws -> (DesignDocument, SketchSpline) {
        var document = DesignDocument.empty()
        let featureID = try document.createSplineSketch(name: "Extend", plane: .xy, spline: spline)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first,
              let sceneNodeID = document.productMetadata.sceneNodes.first(where: { $0.value.reference?.featureID == featureID })?.key else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        try document.extendSketchCurve(
            target: SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(.sketchControlPoint(featureID: featureID, entityID: entityID, index: atStart ? 0 : 3))),
            distance: mm(length),
            shape: shape
        )
        guard case .sketch(let result) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let extended) = result.entities[entityID] else {
            throw EditorError(code: .referenceUnresolved, message: "The spline is missing.")
        }
        return (document, extended)
    }

    /// Signed curvature on each side of the joint knot `u`.
    private func curvatures(_ document: DesignDocument, _ spline: SketchSpline, at u: Double) throws -> (Double, Double) {
        let curve = try document.resolvedSketchSplineCurve(spline, owner: "Test").bSpline
        func k(_ v: Double) throws -> Double {
            let g = try curve.differentialGeometry(at: v, tolerance: .standard)
            return (g.firstDerivative.x * g.secondDerivative.y - g.firstDerivative.y * g.secondDerivative.x) / pow(hypot(g.firstDerivative.x, g.firstDerivative.y), 3)
        }
        return (try k(u - 1e-9), try k(u + 1e-9))
    }

    @Test(arguments: [ExtendCurveShape.soft, .arc, .reflective])
    func theEndKeepsItsTangentAndCurvature(shape: ExtendCurveShape) throws {
        let (document, result) = try extended(shape)
        #expect(result.controlPoints.count > 4)
        let (before, after) = try curvatures(document, result, at: 1)
        #expect(abs(before - after) <= 1e-4 * max(1, abs(before)))
    }

    @Test func anArcExtensionRunsAlongTheEndsCircle() throws {
        let (document, result) = try extended(.arc, length: 4)
        let curve = try document.resolvedSketchSplineCurve(result, owner: "Test")
        let (before, _) = try curvatures(document, result, at: 1)
        // Every point past the joint lies on the osculating circle at the end.
        let g = try curve.bSpline.differentialGeometry(at: 1, tolerance: .standard)
        let t = Point2D(x: g.firstDerivative.x / hypot(g.firstDerivative.x, g.firstDerivative.y), y: g.firstDerivative.y / hypot(g.firstDerivative.x, g.firstDerivative.y))
        let center = Point2D(x: g.position.x - t.y / before, y: g.position.y + t.x / before)
        let (_, upper) = curve.domain
        for i in 1...20 {
            let p = try curve.bSpline.point(at: 1 + (upper - 1) * Double(i) / 20, tolerance: .standard)
            #expect(abs(hypot(p.x - center.x, p.y - center.y) - abs(1 / before)) <= 2e-6)
        }
    }

    @Test func aReflectiveExtensionMirrorsTheEnd() throws {
        let (document, result) = try extended(.reflective, atStart: true, length: 3)
        // The start was extended: the original start (0, 0) is now interior, and the new start
        // mirrors a point of the original across the start's normal.
        let first = result.controlPoints[0]
        let x = try document.cadDocument.parameters.resolvedValue(for: first.x).value
        let y = try document.cadDocument.parameters.resolvedValue(for: first.y).value
        // The start tangent is along (3, 4)/5; the mirror keeps the distance to the normal line.
        let along = (x * 0.6 + y * 0.8) * 1000
        #expect(along < 0)
        let resolved = try result.controlPoints.map { point in
            [try document.cadDocument.parameters.resolvedValue(for: point.x).value, try document.cadDocument.parameters.resolvedValue(for: point.y).value]
        }
        #expect(resolved.contains([0, 0]))
    }

    /// The new points are expressions of the curve's points and the distance: changing a
    /// parameter the end or the distance references moves the extension with them, and the
    /// joint keeps its curvature.
    @Test(arguments: [ExtendCurveShape.soft, .arc, .reflective])
    func theExtensionFollowsTheCurveAndDistanceParameters(shape: ExtendCurveShape) throws {
        var document = DesignDocument.empty()
        let tipID = ParameterID(), reachID = ParameterID()
        document.cadDocument.parameters.parameters[tipID] = Parameter(id: tipID, name: "tip", expression: mm(3), kind: .length)
        document.cadDocument.parameters.parameters[reachID] = Parameter(id: reachID, name: "reach", expression: mm(4), kind: .length)
        var parametric = spline
        parametric.controlPoints[3] = SketchPoint(x: mm(10), y: .reference(tipID))
        let featureID = try document.createSplineSketch(name: "Extend", plane: .xy, spline: parametric)
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let entityID = sketch.entities.keys.first,
              let sceneNodeID = document.productMetadata.sceneNodes.first(where: { $0.value.reference?.featureID == featureID })?.key else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        try document.extendSketchCurve(
            target: SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(.sketchControlPoint(featureID: featureID, entityID: entityID, index: 3))),
            distance: .reference(reachID),
            shape: shape
        )
        guard case .sketch(let result) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              case .spline(let extended) = result.entities[entityID] else {
            throw EditorError(code: .referenceUnresolved, message: "The spline is missing.")
        }
        func added(_ document: DesignDocument) throws -> [Point2D] {
            try extended.controlPoints.dropFirst(4).map {
                Point2D(x: try document.cadDocument.parameters.resolvedValue(for: $0.x).value,
                        y: try document.cadDocument.parameters.resolvedValue(for: $0.y).value)
            }
        }
        #expect(extended.controlPoints.dropFirst(4).allSatisfy {
            if case .bezierShapedExtension = $0.x, case .bezierShapedExtension = $0.y { return true }
            return false
        })
        let before = try added(document)

        document.cadDocument.parameters.parameters[tipID]?.expression = mm(3.4)
        let moved = try added(document)
        #expect(zip(before, moved).contains { hypot($0.x - $1.x, $0.y - $1.y) > 1e-6 })
        let (left, right) = try curvatures(document, extended, at: 1)
        #expect(abs(left - right) <= 1e-4 * max(1, abs(left)))

        document.cadDocument.parameters.parameters[reachID]?.expression = mm(4.5)
        let reached = try added(document)
        #expect(hypot(reached[reached.count - 1].x - moved[moved.count - 1].x, reached[reached.count - 1].y - moved[moved.count - 1].y) > 1e-5)
    }
}
