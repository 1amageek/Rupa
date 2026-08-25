import SwiftCAD
import Testing
@testable import RupaCore

@Test func patternArrayCurvePathGeometryServiceResolvesRatioDistribution() throws {
    let curve = CurvePatternArray(
        path: .polyline(
            points: [
                .origin,
                Point3D(x: 0.1, y: 0.0, z: 0.0),
            ],
            normal: .unitZ
        ),
        copyCount: 2,
        extent: .scalar(0.4),
        extentMode: .ratio
    )

    let geometry = try PatternArrayCurvePathGeometryService().distributionGeometry(
        for: curve,
        parameters: ParameterTable(),
        cadDocument: nil
    )
    let sample = try geometry.path.sample(at: geometry.distributionLength)

    #expect(abs(geometry.path.totalLength - 0.1) < 1.0e-12)
    #expect(abs(geometry.distributionLength - 0.04) < 1.0e-12)
    #expect(abs(sample.point.x - 0.04) < 1.0e-12)
    #expect(abs(sample.point.y) < 1.0e-12)
    #expect(abs(sample.point.z) < 1.0e-12)
}

@Test func patternArrayCurvePathGeometryServiceRejectsDistancePastPathLength() throws {
    let curve = CurvePatternArray(
        path: .polyline(
            points: [
                .origin,
                Point3D(x: 0.05, y: 0.0, z: 0.0),
            ],
            normal: .unitZ
        ),
        copyCount: 2,
        extent: .length(0.08, .meter),
        extentMode: .distance
    )

    #expect(throws: EditorError.self) {
        try PatternArrayCurvePathGeometryService().distributionGeometry(
            for: curve,
            parameters: ParameterTable(),
            cadDocument: nil
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func curvePatternPathSamplerUsesCanonicalRigidImageGeometry() throws {
    let tolerance = ModelingTolerance.standard
    let spline = BSplineCurve3D(
        degree: 3,
        knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
        controlPoints: [
            .origin,
            Point3D(x: 0.0, y: 4.0, z: 0.0),
            Point3D(x: 2.0, y: 6.0, z: 0.0),
            Point3D(x: 8.0, y: 6.0, z: 0.0),
        ]
    )
    let transform = try RigidTransform3D.rotated(
        around: .origin,
        direction: .unitZ,
        angle: Double.pi * 0.5,
        tolerance: tolerance
    )
    let exactCurve = Curve3D.rigidImage(try RigidImageCurve3D(
        source: .bSpline(spline),
        transform: transform,
        tolerance: tolerance
    ))
    let endpoints = try [0.0, 1.0].map {
        try exactCurve.point(at: $0, tolerance: tolerance)
    }
    let evaluated = EvaluatedCurve(
        sourceFeatureID: FeatureID(),
        source: .generatedFeature,
        kind: .spline,
        points: endpoints,
        exactCurve: exactCurve,
        exactParameterDomain: .closed(0.0, 1.0),
        exactPointParameters: [0.0, 1.0]
    )
    let geometry = try CurvePatternPathSampler(tolerance: tolerance).geometry(
        for: evaluated,
        referenceNormal: .unitZ
    )
    let sample = try geometry.sample(
        at: geometry.totalLength * 0.5,
        tolerance: tolerance
    )
    let expectedParameter = try DefaultCurveArcLengthResolver()
        .parameterEnclosure(
            atArcLengthFraction: 0.5,
            of: exactCurve,
            over: ScalarInterval(lower: 0.0, upper: 1.0),
            tolerance: tolerance
        ).parameter
    let expected = try exactCurve.differentialGeometry(
        at: expectedParameter,
        tolerance: tolerance
    )
    let chordMidpoint = endpoints[0] + (endpoints[1] - endpoints[0]) * 0.5

    #expect((sample.point - expected.position).length <= tolerance.distance)
    #expect(sample.tangent.dot(expected.tangent) >= 1.0 - tolerance.angle)
    #expect((sample.point - chordMidpoint).length > tolerance.distance * 100.0)
}
