import Testing
@testable import RupaGeometry

@Test(.timeLimit(.minutes(1)))
func nurbsLinearCurveEvaluatesItsParameterDomain() throws {
    let curve = try NURBSCurve(
        degree: 1,
        controlPoints: GeometryBuffer([
            GeometryPoint3D(x: 0, y: 0, z: 0),
            GeometryPoint3D(x: 2, y: 0, z: 0),
        ]),
        weights: GeometryBuffer([1.0, 1.0]),
        knots: GeometryBuffer([0.0, 0.0, 1.0, 1.0])
    )

    #expect(try curve.evaluate(at: 0.0) == GeometryPoint3D(x: 0, y: 0, z: 0))
    #expect(try curve.evaluate(at: 0.5) == GeometryPoint3D(x: 1, y: 0, z: 0))
    #expect(try curve.evaluate(at: 1.0) == GeometryPoint3D(x: 2, y: 0, z: 0))
}

@Test(.timeLimit(.minutes(1)))
func nurbsRationalQuadraticCurveUsesWeights() throws {
    let curve = try NURBSCurve(
        degree: 2,
        controlPoints: GeometryBuffer([
            GeometryPoint3D(x: 1, y: 0, z: 0),
            GeometryPoint3D(x: 1, y: 1, z: 0),
            GeometryPoint3D(x: 0, y: 1, z: 0),
        ]),
        weights: GeometryBuffer([1.0, Double(2.0.squareRoot()) / 2.0, 1.0]),
        knots: GeometryBuffer([0.0, 0.0, 0.0, 1.0, 1.0, 1.0])
    )
    let midpoint = try curve.evaluate(at: 0.5)

    #expect(abs(midpoint.x - Double(0.5.squareRoot())) < 0.000_001)
    #expect(abs(midpoint.y - Double(0.5.squareRoot())) < 0.000_001)
    #expect(midpoint.z == 0)
}

@Test(.timeLimit(.minutes(1)))
func nurbsCurveRejectsInvalidWeightsAndKnotOrder() throws {
    var weightError: NURBSCurveError?
    do {
        _ = try NURBSCurve(
            degree: 1,
            controlPoints: GeometryBuffer([
                GeometryPoint3D(x: 0, y: 0, z: 0),
                GeometryPoint3D(x: 1, y: 0, z: 0),
            ]),
            weights: GeometryBuffer([1.0, 0.0]),
            knots: GeometryBuffer([0.0, 0.0, 1.0, 1.0])
        )
    } catch let caught as NURBSCurveError {
        weightError = caught
    }
    #expect(weightError?.code == .invalidWeight)

    var knotError: NURBSCurveError?
    do {
        _ = try NURBSCurve(
            degree: 1,
            controlPoints: GeometryBuffer([
                GeometryPoint3D(x: 0, y: 0, z: 0),
                GeometryPoint3D(x: 1, y: 0, z: 0),
            ]),
            weights: GeometryBuffer([1.0, 1.0]),
            knots: GeometryBuffer([0.0, 0.5, 0.25, 1.0])
        )
    } catch let caught as NURBSCurveError {
        knotError = caught
    }
    #expect(knotError?.code == .invalidKnotVector)
}
