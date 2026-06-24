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
