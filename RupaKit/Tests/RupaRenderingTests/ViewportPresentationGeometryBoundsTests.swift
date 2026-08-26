import CoreGraphics
import RupaCore
import RupaGeometry
import RupaViewportScene
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func viewportPresentationGeometryBoundsFrameTranslatedMeshWithoutLegacyCADBounds() throws {
    let bounds = try GeometryBounds3D(
        minimum: GeometryPoint3D(x: 100, y: 20, z: 200),
        maximum: GeometryPoint3D(x: 104, y: 24, z: 208)
    )
    let size = CGSize(width: 500, height: 400)
    let context = ViewportSceneContext(
        ruler: .standard(for: .millimeter),
        scene: ViewportScene(items: []),
        size: size,
        basis: .isometric,
        geometryBoundsSource: .geometry(bounds)
    )

    let projectedCenter = context.layout.project(
        Point3D(x: 102, y: 22, z: 204)
    )

    #expect(abs(projectedCenter.x - size.width * 0.5) < 0.001)
    #expect(abs(projectedCenter.y - size.height * 0.5) < 0.001)
}
