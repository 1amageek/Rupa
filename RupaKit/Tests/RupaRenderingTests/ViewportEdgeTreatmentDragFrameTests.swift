import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Suite struct ViewportEdgeTreatmentDragFrameTests {
    @Test func dragFollowsDisplayedNormalInSourceUnits() throws {
        let anchor = Point3D(x: 1, y: 2, z: 3)
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: anchor)
        let start = measure.projected(anchor)
        for scaleX in [-2.0, 0.5, 1.0, 2.0] {
            let placement = try ScenePlacement(Transform3D.scale(
                Vector3D(x: scaleX, y: 2, z: 3), about: .origin))
            for axis in [measure.up, measure.right, Vector3D.unitZ] {
                let frame = ViewportEdgeTreatmentDragFrame(
                    anchor: anchor, direction: axis, modelTransform: placement)
                let sourceUnits = Vector3D(x: axis.x / scaleX, y: axis.y / 2, z: axis.z / 3).length
                for travel in [-0.002, 0.0, 0.002] {
                    let end = measure.projected(anchor + axis * travel)
                    let value = try frame.distance(from: start, to: end, measure: measure)
                    #expect(abs(value - travel * sourceUnits) < 1e-12)
                }
                let projectedAxis = measure.projected(anchor + axis * 0.002)
                let perpendicular = CGPoint(x: start.x - (projectedAxis.y - start.y),
                                            y: start.y + (projectedAxis.x - start.x))
                #expect(abs(try frame.distance(from: start, to: perpendicular, measure: measure)) < 1e-12)
                #expect(throws: (any Error).self) {
                    try frame.distance(from: start, to: CGPoint(x: CGFloat.nan, y: 0), measure: measure)
                }
            }
        }
        for axis in [Vector3D.zero, measure.forward] {
            let frame = ViewportEdgeTreatmentDragFrame(
                anchor: anchor, direction: axis, modelTransform: .identity)
            #expect(throws: (any Error).self) {
                try frame.distance(from: start, to: CGPoint(x: 450, y: 350), measure: measure)
            }
        }
    }
}
