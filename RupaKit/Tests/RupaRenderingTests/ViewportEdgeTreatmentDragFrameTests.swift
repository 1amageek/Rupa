import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Suite struct ViewportEdgeTreatmentDragFrameTests {
    @Test func sourceLengthIsIndependentOfProfileAndOccurrenceScale() throws {
        let anchor = Point3D(x: 1, y: 2, z: 3)
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: anchor)
        for scale in [0.5, 1.0, 2.0] {
            let frame = try ViewportEdgeTreatmentDragFrame(anchor: anchor,
                modelTransform: ViewportWorldTransformAlgebra.scale(scale, about: .origin))
            let start = CGPoint(x: 400, y: 300)
            for travel in [-40.0, 0.0, 40.0] {
                let value = try frame.distance(from: start,
                    to: CGPoint(x: 400 + travel, y: 350), measure: measure)
                #expect(abs(value - travel / measure.scale / scale) < 1e-12)
            }
            #expect(throws: (any Error).self) {
                try frame.distance(from: start, to: CGPoint(x: CGFloat.nan, y: 0), measure: measure)
            }
        }
    }
}
