import SwiftCAD
import Testing
@testable import RupaCore

/// Covers the construction boundary and mapping arithmetic of validated scene placements.
@Suite struct ScenePlacementTests {
    private let tolerance = 1.0e-12

    @Test func constructionRejectsMalformedProjectiveAndSingularMatrices() throws {
        var malformed = Transform3D.identity
        malformed.matrix.values = [1]
        var projective = Transform3D.identity
        projective.matrix.values[12] = 1
        var singular = Transform3D.identity
        singular.matrix.values[0] = 0

        for transform in [malformed, projective, singular] {
            #expect(throws: EditorError.self) {
                _ = try ScenePlacement(transform)
            }
        }
    }

    @Test func forwardAndInverseMappingsAgreeWithCheckedTransformOperations() throws {
        let transform = try Transform3D.translation(Vector3D(x: 10, y: 20, z: 30))
            .composed(with: .scale(Vector3D(x: -2, y: 3, z: 4), about: .origin))
            .composed(with: .rotation(axis: .unitZ, angleRadians: .pi / 3.0))
        let placement = try ScenePlacement(transform)
        let point = Point3D(x: 1.5, y: -0.25, z: 2.0)
        let vector = Vector3D(x: 0.002, y: 0.003, z: 0.004)

        let mappedPoint = placement.point(point)
        let mappedVector = placement.vector(vector)

        #expect(mappedPoint.isApproximatelyEqual(to: try transform.applied(to: point), tolerance: tolerance))
        #expect((mappedVector - (try transform.applyingLinearPart(to: vector))).length < tolerance)
        #expect(placement.inversePoint(mappedPoint).isApproximatelyEqual(to: point, tolerance: 1.0e-9))
        #expect((placement.inverseVector(mappedVector) - vector).length < tolerance)
        #expect(placement.translation == Vector3D(x: 10, y: 20, z: 30))
    }

    @Test func normalsFollowTheInverseTransposeUnderNonUniformScale() throws {
        // A plane tilted 45 degrees in XZ: stretching X by 2 tilts its normal toward Z.
        let placement = try ScenePlacement(.scale(Vector3D(x: 2, y: 1, z: 1), about: .origin))
        let normal = placement.normal(Vector3D(x: 1, y: 0, z: 1))
        let inPlane = placement.vector(Vector3D(x: 1, y: 0, z: -1))

        #expect(abs(normal.dot(inPlane)) < tolerance)
        #expect(abs(normal.x - 0.5) < tolerance)
        #expect(abs(normal.z - 1.0) < tolerance)
    }

    @Test func compositionRevalidatesAndInverseUndoesThePlacement() throws {
        let placement = try ScenePlacement(.translation(Vector3D(x: 1, y: 2, z: 3)))
        let rotation = try ScenePlacement(.rotation(axis: .unitY, angleRadians: .pi / 2.0))
        let composed = try placement.composed(with: rotation)
        let roundTrip = try composed.composed(with: composed.inverse)
        let point = Point3D(x: 4, y: 5, z: 6)

        #expect(composed.point(point).isApproximatelyEqual(
            to: placement.point(rotation.point(point)),
            tolerance: tolerance
        ))
        #expect(roundTrip.point(point).isApproximatelyEqual(to: point, tolerance: 1.0e-9))
        #expect(ScenePlacement.identity.point(point) == point)
    }
}
