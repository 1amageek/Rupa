import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Scene composition storage convention", .timeLimit(.minutes(1)))
struct SceneCompositionMatrixTests {
    @Test func explicitRowMajorMatricesAgreeWithSceneHelpers() throws {
        let translation = try Transform3D.translation(Vector3D(x: 2, y: 3, z: 4))
        #expect(translation.matrix.values == [1, 0, 0, 2, 0, 1, 0, 3, 0, 0, 1, 4, 0, 0, 0, 1])
        let rotation = try Transform3D.rotation(axis: .unitZ, angleRadians: .pi / 2)
        let expected = [0.0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        for (actual, value) in zip(rotation.matrix.values, expected) {
            #expect(abs(actual - value) < 1e-12)
        }
        let world = try translation.composed(with: rotation)
        let point = Point3D(x: 1, y: 0, z: 0)
        #expect(try (world.applied(to: point) - Point3D(x: 2, y: 4, z: 4)).length < 1e-12)
        #expect(try (world.inverse().applied(to: Point3D(x: 2, y: 4, z: 4)) - point).length < 1e-12)
        let affine = Transform3D(matrix: try Matrix4x4(values: [
            -2, 0.5, 0, 2, 0, 3, 0.25, 3, 0, 0, 4, 4, 0, 0, 0, 1
        ]))
        let product = try affine.composed(with: rotation)
        #expect(try (product.applied(to: point) - Point3D(x: 2.5, y: 6, z: 4)).length < 1e-12)
        #expect(try (affine.inverse().applied(to: affine.applied(to: point)) - point).length < 1e-12)
        let singular = Transform3D(matrix: try Matrix4x4(values: Array(repeating: 0, count: 16)))
        #expect(throws: EditorError.self) { try singular.inverse() }
    }
}
