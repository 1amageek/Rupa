import Testing
import RupaCore
import RupaGeometry
import RupaViewportScene
@testable import RupaUI

@Suite("Workspace TRS matrix", .timeLimit(.minutes(1)))
struct WorkspaceTransformMatrixTests {
    @Test func rowMajorTranslationAgreesWithPresentationAndOverlay() throws {
        let transform = try WorkspaceTransformMatrix.replacing(.translationX, with: 2, in: .identity)
        #expect(transform.matrix.values[3] == 2)
        #expect(transform.matrix.values[12] == 0)
        let point = Point3D(x: 1, y: 2, z: 3)
        let overlay = ViewportLayout.transformedPoint(point, by: transform)
        let presentation = try GeometryTransform3D(values: transform.matrix.values).applying(to: GeometryPoint3D(x: point.x, y: point.y, z: point.z))
        #expect(overlay == Point3D(x: presentation.x, y: presentation.y, z: presentation.z))
        #expect(overlay == Point3D(x: 3, y: 2, z: 3))
    }

    @Test func rotationsAndScalePreserveTheOtherComponents() throws {
        var transform = try WorkspaceTransformMatrix.replacing(.rotationZ, with: 90, in: .identity)
        transform = try WorkspaceTransformMatrix.replacing(.scaleX, with: 2, in: transform)
        transform = try WorkspaceTransformMatrix.replacing(.translationY, with: 4, in: transform)
        let result = ViewportLayout.transformedPoint(Point3D(x: 1, y: 0, z: 0), by: transform)
        #expect(abs(result.x) < 1e-12)
        #expect(abs(result.y - 6) < 1e-12)
        let components = try WorkspaceTransformMatrix.components(of: transform)
        #expect(abs(components.rotationDegrees.z - 90) < 1e-12)
        #expect(abs(components.scale.x - 2) < 1e-12)
        #expect(components.translation.y == 4)
    }

    @Test func mirroredAndGimbalLockedTransformsRoundTrip() throws {
        for y in [-90.0, -30, 45, 90] {
            let transform = try WorkspaceTransformMatrix.transform(from: .init(
                translation: .init(x: 1, y: 2, z: 3),
                rotationDegrees: .init(x: 20, y: y, z: 70),
                scale: .init(x: -2, y: 3, z: 4)
            ))
            let roundTrip = try WorkspaceTransformMatrix.transform(from: WorkspaceTransformMatrix.components(of: transform))
            #expect(zip(transform.matrix.values, roundTrip.matrix.values).allSatisfy { abs($0 - $1) < 1e-9 })
        }
    }

    @Test func unsupportedMatricesAndNumbersFailInsteadOfResetting() throws {
        var shear = Matrix4x4.identity.values
        shear[1] = 0.3
        var perspective = Matrix4x4.identity.values
        perspective[12] = 0.2
        for values in [shear, perspective] {
            let transform = Transform3D(matrix: try Matrix4x4(values: values))
            #expect(throws: EditorError.self) { try WorkspaceTransformMatrix.components(of: transform) }
        }
        for value in [0.0, Double.nan, Double.infinity] {
            #expect(throws: EditorError.self) { try WorkspaceTransformMatrix.replacing(.scaleX, with: value, in: .identity) }
        }
    }
}
