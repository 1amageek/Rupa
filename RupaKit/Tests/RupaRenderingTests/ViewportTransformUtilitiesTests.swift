import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func viewportTransformInverseRoundTripsRotatedVectors() throws {
    let transform = Transform3D(matrix: try Matrix4x4(values: [
        0.0, 0.0, 1.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        -1.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]))
    let vector = Vector3D(x: 0.002, y: 0.003, z: 0.004)
    let transformed = transform.viewportTransformedVector(vector)
    let inverted = try #require(transform.viewportInverseTransformedVector(transformed))

    #expect(abs(inverted.x - vector.x) < 1.0e-12)
    #expect(abs(inverted.y - vector.y) < 1.0e-12)
    #expect(abs(inverted.z - vector.z) < 1.0e-12)
}
