import SwiftCAD
import Testing
@testable import RupaCore

@Test func cadInputValueNormalizerSnapsBinaryFloatingPointNoise() {
    let normalizer = CADInputValueNormalizer.standard

    #expect(normalizer.lengthMeters(0.03 - 0.05) == -0.02)
    #expect(normalizer.lengthMeters(0.01 + 0.02) == 0.03)
    #expect(normalizer.angleDegrees((Double.pi / 6.0) * 180.0 / .pi) == 30.0)
}

@Test func cadInputValueNormalizerNormalizesPointCoordinates() {
    let normalizer = CADInputValueNormalizer.standard
    let point = normalizer.point(
        Point2D(
            x: -0.01 - Double.ulpOfOne,
            y: 0.01 + Double.ulpOfOne
        )
    )

    #expect(point == Point2D(x: -0.01, y: 0.01))
}
