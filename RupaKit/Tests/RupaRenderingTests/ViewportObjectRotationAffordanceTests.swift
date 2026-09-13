import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func objectEditProjectionUsesTheFullPerspectivePoint() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -2, y: -2, width: 4, height: 4),
        size: CGSize(width: 800, height: 600),
        camera: ViewportCamera(projection: .standardPerspective),
        verticalBounds: -2...2
    )
    let state = ViewportObjectEditState(xMin: -1, xMax: 1, yMin: -1, yMax: 1, zMin: -1, zMax: 1)
    let model = ViewportModelPoint3D(x: 0.2, y: 0.8, z: 0.3)
    let actual = try #require(state.projectedPoint(model, layout: layout))
    let expected = try #require(layout.projectedPoint(Point3D(x: 0.2, y: 0.8, z: 0.3))).point
    #expect(hypot(actual.x - expected.x, actual.y - expected.y) < 1e-9)

    let ray = try #require(layout.viewportRay(for: layout.fittingCenter))
    let hidden = Point3D(
        x: ray.origin.x - ray.direction.x,
        y: ray.origin.y - ray.direction.y,
        z: ray.origin.z - ray.direction.z
    )
    let invisible = ViewportObjectEditState(
        xMin: CGFloat(hidden.x) - 0.01, xMax: CGFloat(hidden.x) + 0.01,
        yMin: CGFloat(hidden.y) - 0.01, yMax: CGFloat(hidden.y) + 0.01,
        zMin: CGFloat(hidden.z) - 0.01, zMax: CGFloat(hidden.z) + 0.01
    )
    #expect(invisible.projectedPoint(invisible.centerPoint, layout: layout) == nil)
}

@Test func placementFootprintHighlightMatchesClickPlacement() throws {
    let footprint = try #require(ViewportPlacementFootprint(
        centeredAt: Point2D(x: 0.010, y: 0.020),
        sideMeters: 0.004,
        sketchPlane: .zx
    ))
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: .zx)
    let bottomLeft = coordinateSystem.project(footprint.bottomLeft).point
    let bottomRight = coordinateSystem.project(footprint.bottomRight).point
    let topRight = coordinateSystem.project(footprint.topRight).point
    let topLeft = coordinateSystem.project(footprint.topLeft).point

    #expect(abs((bottomLeft.x + topRight.x) / 2.0 - 0.020) < 1.0e-12)
    #expect(abs((bottomLeft.y + topRight.y) / 2.0 - 0.010) < 1.0e-12)
    #expect(abs(bottomRight.x - bottomLeft.x - 0.004) < 1.0e-12)
    #expect(abs(topLeft.y - bottomLeft.y - 0.004) < 1.0e-12)
    #expect(abs(topRight.x - topLeft.x - 0.004) < 1.0e-12)
    #expect(abs(topRight.y - bottomRight.y - 0.004) < 1.0e-12)

    #expect(ViewportPlacementFootprint(
        centeredAt: Point2D(x: 0.0, y: 0.0),
        sideMeters: 0.0,
        sketchPlane: .zx
    ) == nil)
    #expect(ViewportPlacementFootprint(
        centeredAt: Point2D(x: 0.0, y: 0.0),
        sideMeters: .infinity,
        sketchPlane: .zx
    ) == nil)
}

@Test func placementFootprintUsesCustomConstructionPlane() throws {
    let sketchPlane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 0.10, y: 0.20, z: 0.30),
            normal: Vector3D(x: 0.0, y: 1.0, z: 0.0)
        )
    )
    let footprint = try #require(ViewportPlacementFootprint(
        centeredAt: Point2D(x: 0.030, y: -0.020),
        sideMeters: 0.006,
        sketchPlane: sketchPlane
    ))
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
    let projectedPoints = [
        coordinateSystem.project(footprint.bottomLeft),
        coordinateSystem.project(footprint.bottomRight),
        coordinateSystem.project(footprint.topRight),
        coordinateSystem.project(footprint.topLeft),
    ]

    for point in projectedPoints {
        #expect(abs(point.depth) < 1.0e-12)
    }

    #expect(abs(projectedPoints[0].point.x - 0.027) < 1.0e-12)
    #expect(abs(projectedPoints[0].point.y + 0.023) < 1.0e-12)
    #expect(abs(projectedPoints[2].point.x - 0.033) < 1.0e-12)
    #expect(abs(projectedPoints[2].point.y + 0.017) < 1.0e-12)
}
