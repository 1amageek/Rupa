import CoreGraphics
import RupaCore
@testable import RupaRendering
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaGeometry

@Test
func perspectiveProjectionRejectsBehindCameraPointsAndPreservesNearPlaneContract() throws {
    let camera = ViewportCamera(projection: .standardPerspective)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -2.0, y: -2.0, width: 4.0, height: 4.0),
        size: CGSize(width: 1000.0, height: 800.0),
        camera: camera,
        basis: .isometric,
        verticalBounds: -2.0...2.0
    )
    let target = layout.renderOrigin
    let projectedTarget = try #require(layout.projectedPoint(target))
    #expect(abs(projectedTarget.point.x - layout.fittingCenter.x) < 1.0e-8)
    #expect(abs(projectedTarget.point.y - layout.fittingCenter.y) < 1.0e-8)
    #expect(projectedTarget.depth > 0.0)

    let centerRay = try #require(layout.viewportRay(for: layout.fittingCenter))
    let behindCamera = translated(centerRay.origin, by: centerRay.direction, scale: -1.0)
    #expect(layout.projectedPoint(behindCamera) == nil)

    let nearCrossing = translated(centerRay.origin, by: centerRay.direction, scale: 1.0e-8)
    #expect(layout.projectedPoint(nearCrossing) == nil)
}

@Test
func perspectiveProjectionRoundTripsTheDisplayedCanvasPlane() throws {
    for basis in [ViewportProjectionBasis.isometric, .axisFront(.x), .axisFront(.y), .axisFront(.z)] {
        let plane = ViewportCanvasPlane.displayed(for: basis)
        let layout = ViewportLayout(
            modelBounds: CGRect(x: -4.0, y: -4.0, width: 8.0, height: 8.0),
            size: CGSize(width: 900.0, height: 700.0),
            camera: ViewportCamera(
                zoom: 1.25,
                pan: CGSize(width: 23.0, height: -17.0),
                projection: .perspective(fieldOfViewRadians: .pi / 3.0)
            ),
            basis: basis,
            verticalBounds: -2.0...2.0,
            fittingInsets: .init(top: 20, leading: 60, bottom: 40, trailing: 10)
        )
        let worldPoint = plane.worldPoint(first: 0.7, second: -1.1)
        let screenPoint = try #require(layout.projectedPoint(worldPoint)).point
        let roundTrip = try #require(layout.unproject(screenPoint, onto: plane))
        #expect(roundTrip.isApproximatelyEqual(to: worldPoint, tolerance: 1.0e-8))
    }
}

@Test
func projectionRowsMatchWorldProjectionWhenMeshPositionsUseAnOrigin() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -3.0, y: -2.0, width: 6.0, height: 4.0),
        size: CGSize(width: 800.0, height: 600.0),
        camera: ViewportCamera(
            projection: .perspective(fieldOfViewRadians: .pi / 3.0)
        ),
        basis: .orbit(yaw: 0.3, elevation: 0.5),
        verticalBounds: -1.0...2.0
    )
    let origin = Point3D(x: 1.2, y: -0.4, z: 0.8)
    let local = Point3D(x: 0.3, y: 0.5, z: -0.2)
    let world = translated(origin, by: Vector3D(x: local.x, y: local.y, z: local.z))
    let localRows = try #require(layout.projectionRows(relativeTo: origin))
    let worldRows = try #require(layout.projectionRows(relativeTo: Point3D.origin))
    let localHomogeneous = localRows.evaluate(local)
    let worldHomogeneous = worldRows.evaluate(world)
    #expect(abs(localHomogeneous.x - worldHomogeneous.x) < 1.0e-9)
    #expect(abs(localHomogeneous.y - worldHomogeneous.y) < 1.0e-9)
    #expect(abs(localHomogeneous.depth - worldHomogeneous.depth) < 1.0e-9)
    #expect(abs(localHomogeneous.w - worldHomogeneous.w) < 1.0e-9)
}

@Test
func perspectiveFitUsesTheSameVisibleProjectionForAllBoundsCorners() throws {
    let bounds = try GeometryBounds3D(
        minimum: GeometryPoint3D(x: -1.5, y: -0.8, z: -1.2),
        maximum: GeometryPoint3D(x: 2.0, y: 1.4, z: 1.6)
    )
    let size = CGSize(width: 1000.0, height: 700.0)
    let insets = ViewportLayout.FittingInsets(top: 36.0, leading: 52.0, bottom: 48.0, trailing: 24.0)
    let projection = ViewportCameraProjection.standardPerspective
    let camera = try ViewportControlBoundsSolver.camera(
        for: bounds,
        sceneModelBounds: CGRect(x: -3.0, y: -3.0, width: 6.0, height: 6.0),
        verticalBounds: -2.0...2.0,
        basis: .isometric,
        size: size,
        fittingInsets: insets,
        maximumZoom: 32.0,
        projection: projection
    )
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -3.0, y: -3.0, width: 6.0, height: 6.0),
        size: size,
        camera: camera,
        basis: .isometric,
        maximumZoom: 32.0,
        verticalBounds: -2.0...2.0,
        fittingInsets: insets
    )
    let fitting = insets.fittingRect(in: size).insetBy(dx: -1.0e-4, dy: -1.0e-4)
    for index in 0..<8 {
        let point = Point3D(
            x: index & 1 == 0 ? bounds.minimum.x : bounds.maximum.x,
            y: index & 2 == 0 ? bounds.minimum.y : bounds.maximum.y,
            z: index & 4 == 0 ? bounds.minimum.z : bounds.maximum.z
        )
        let projected = try #require(layout.projectedPoint(point)).point
        #expect(fitting.contains(projected))
    }
    #expect(camera.projection == projection)
}

private func translated(_ point: Point3D, by vector: Vector3D, scale: Double = 1.0) -> Point3D {
    Point3D(
        x: point.x + vector.x * scale,
        y: point.y + vector.y * scale,
        z: point.z + vector.z * scale
    )
}

@Test
func perspectiveFramingTranslatesTheCameraAndRetainsDepthParallax() throws {
    let size = CGSize(width: 900, height: 700)
    let basis = ViewportProjectionBasis.axisFront(.z)
    let camera = ViewportCamera(pan: CGSize(width: 23, height: -17), projection: .standardPerspective)
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -4, y: -4, width: 8, height: 8), size: size,
        camera: camera, basis: basis, verticalBounds: -2...2,
        fittingInsets: .init(top: 20, leading: 60, bottom: 40, trailing: 10)
    )
    let normal = try #require(basis.viewNormal)
    let viewportCenter = CGPoint(x: size.width / 2, y: size.height / 2)
    let ray = try #require(layout.viewportRay(for: viewportCenter))
    let distance = (ray.origin - layout.focus).dot(normal)
    let nearPoint = layout.focus + normal * (distance * 0.5)
    let farPoint = layout.focus + normal * (-distance)
    for (point, parallax) in [(layout.focus, 1.0), (nearPoint, 2.0), (farPoint, 0.5)] {
        let projected = try #require(layout.projectedPoint(point)).point
        #expect(abs(projected.x - viewportCenter.x - (layout.center.x - viewportCenter.x) * parallax) < 1e-8)
        #expect(abs(projected.y - viewportCenter.y - (layout.center.y - viewportCenter.y) * parallax) < 1e-8)
        let pointRay = try #require(layout.viewportRay(for: projected))
        let alongRay = (point - pointRay.origin).dot(pointRay.direction)
        #expect((pointRay.origin + pointRay.direction * alongRay).isApproximatelyEqual(to: point, tolerance: 1e-8))
    }
    #expect(abs(ray.direction.x + normal.x) < 1e-8)
    #expect(abs(ray.direction.y + normal.y) < 1e-8)
    #expect(abs(ray.direction.z + normal.z) < 1e-8)
    var invalidLayout = layout
    invalidLayout.basis.xDirection.dx = 2
    #expect(invalidLayout.projectionRows() == nil)
    #expect(invalidLayout.projectedPoint(layout.focus) == nil)
    #expect(invalidLayout.viewportRay(for: viewportCenter) == nil)
}
