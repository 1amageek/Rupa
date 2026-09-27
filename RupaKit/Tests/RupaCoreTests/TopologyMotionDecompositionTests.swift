import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A body-frame motion reads back as the kernel's typed motion that reproduces it.
@Suite struct TopologyMotionDecompositionTests {
    private func apply(_ motion: TopologyMotion, to point: Point3D) throws -> Point3D {
        switch motion {
        case .translation(let vector):
            let distance = try ParameterTable().resolvedValue(for: vector.distance).value
            return point + vector.direction * distance
        case .rotation(let rotation):
            let angle = try ParameterTable().resolvedValue(for: rotation.angle).value
            return try Transform3D.rotation(axis: rotation.axis, angleRadians: angle, about: rotation.origin).applied(to: point)
        case .scale(let scale):
            let factors = try scale.factors.map { try ParameterTable().resolvedValue(for: $0).value }
            let x = try scale.xAxis.normalized(tolerance: 1e-12), y = try scale.yAxis.normalized(tolerance: 1e-12)
            let offset = point - scale.origin
            let axes = [x, y, x.cross(y)]
            return zip(axes, factors).reduce(scale.origin) { $0 + $1.0 * ($1.0.dot(offset) * $1.1) }
        }
    }

    @Test func movesTurnsAndScalesReadBackExactly() throws {
        let samples = [Point3D(x: 0.1, y: -0.2, z: 0.3), Point3D(x: -0.05, y: 0.4, z: 0), Point3D(x: 1, y: 1, z: 1)]
        let deltas: [Transform3D] = [
            try Transform3D.translation(Vector3D(x: 0.01, y: 0, z: -0.02)),
            try Transform3D.rotation(axis: Vector3D(x: 1, y: 2, z: 3), angleRadians: 0.7, about: Point3D(x: 0.2, y: -0.1, z: 0.05)),
            try Transform3D.rotation(axis: .unitZ, angleRadians: .pi, about: Point3D(x: 1, y: 0, z: 0)),
        ]
        for delta in deltas {
            let motion = try TopologyMotionDecomposition.motion(delta)
            for point in samples {
                #expect((try apply(motion, to: point) - (try delta.applied(to: point))).length < 1e-12)
            }
        }
        // A scale by 2, 1 and 0.5 along a turned frame about a point.
        let frame = try Transform3D.rotation(axis: .unitZ, angleRadians: 0.3, about: Point3D(x: 0.1, y: 0.1, z: 0))
        let diagonal = Transform3D(matrix: try Matrix4x4(values: [2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 1]))
        let scale = try frame.composed(with: diagonal.composed(with: try frame.inverse()))
        let motion = try TopologyMotionDecomposition.motion(scale)
        guard case .scale = motion else {
            Issue.record("Expected a scale.")
            return
        }
        for point in samples {
            #expect((try apply(motion, to: point) - (try scale.applied(to: point))).length < 1e-12)
        }
        let shear = Transform3D(matrix: try Matrix4x4(values: [1, 0.5, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]))
        #expect(throws: EditorError.self) { try TopologyMotionDecomposition.motion(shear) }
    }
}
