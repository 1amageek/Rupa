import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// The constraint propagator holds spline end conditions through the clamped end derivatives of
/// each spline's own degree and knots, so a quintic and a cubic with explicit knots can be joined
/// smoothly (C2) and a move of one end carries the other.
@MainActor
@Suite struct GeneralSplineConstraintPropagationTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private let quinticID = SketchEntityID()
    private let cubicID = SketchEntityID()

    /// A quintic chain ending near (40, 4) and a cubic with one simple interior knot starting near it.
    private func sketch() -> Sketch {
        Sketch(plane: .xy, entities: [
            quinticID: .spline(SketchSpline(
                controlPoints: [point(0, 0), point(8, 8), point(16, -4), point(24, 10), point(32, 2), point(40, 4)],
                degree: 5
            )),
            cubicID: .spline(SketchSpline(
                controlPoints: [point(41, 5), point(48, 9), point(56, 3), point(64, 12), point(72, 0)],
                knots: [0, 0, 0, 0, 0.3, 1, 1, 1, 1]
            )),
        ])
    }

    private func curve(_ id: SketchEntityID, in sketch: Sketch) throws -> BSplineCurve2D {
        guard case let .spline(spline) = sketch.entities[id], let knots = spline.knotVector else {
            throw EditorError(code: .referenceUnresolved, message: "The spline is missing.")
        }
        let points = try spline.controlPoints.map { point -> Point2D in
            Point2D(
                x: try ParameterTable().resolvedValue(for: point.x).value,
                y: try ParameterTable().resolvedValue(for: point.y).value
            )
        }
        return BSplineCurve2D(degree: spline.degree, knots: knots, controlPoints: points)
    }

    @Test func aSmoothJoinMatchesBothDerivativesAcrossDegreesAndKnots() throws {
        var sketch = sketch()
        try SketchPointConstraintPropagator(parameters: ParameterTable()).satisfyAddingConstraint(
            .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                first: SketchSplineEndpointReference(splineID: quinticID, endpoint: .end),
                second: SketchSplineEndpointReference(splineID: cubicID, endpoint: .start),
                orientation: .aligned
            )),
            in: &sketch,
            owner: "Test"
        )
        let end = try curve(quinticID, in: sketch).differentialGeometry(at: 1, tolerance: .standard)
        let start = try curve(cubicID, in: sketch).differentialGeometry(at: 0, tolerance: .standard)
        #expect(hypot(end.position.x - start.position.x, end.position.y - start.position.y) <= 1e-12)
        #expect(hypot(end.firstDerivative.x - start.firstDerivative.x, end.firstDerivative.y - start.firstDerivative.y) <= 1e-9)
        #expect(hypot(end.secondDerivative.x - start.secondDerivative.x, end.secondDerivative.y - start.secondDerivative.y) <= 1e-6)
    }

    @Test func aJointOfAQuinticChainIsSmoothedAtItsDegree() throws {
        let id = SketchEntityID()
        var sketch = Sketch(plane: .xy, entities: [
            id: .spline(SketchSpline(
                controlPoints: (0..<11).map { point(Double($0) * 4, $0.isMultiple(of: 2) ? 0 : 6) },
                degree: 5
            )),
        ])
        try SketchPointConstraintPropagator(parameters: ParameterTable()).satisfyAddingConstraint(
            .smoothSplineControlPoint(entity: id, index: 5),
            in: &sketch,
            owner: "Test"
        )
        let joint = try curve(id, in: sketch)
        let left = try joint.differentialGeometry(at: 1 - 1e-9, tolerance: .standard)
        let right = try joint.differentialGeometry(at: 1 + 1e-9, tolerance: .standard)
        let cross = left.firstDerivative.x * right.firstDerivative.y - left.firstDerivative.y * right.firstDerivative.x
        #expect(abs(cross) <= 1e-6 * hypot(left.firstDerivative.x, left.firstDerivative.y) * hypot(right.firstDerivative.x, right.firstDerivative.y))
        #expect(throws: EditorError.self) {
            var other = sketch
            try SketchPointConstraintPropagator(parameters: ParameterTable()).satisfyAddingConstraint(
                .smoothSplineControlPoint(entity: id, index: 3), in: &other, owner: "Test"
            )
        }
    }
}
