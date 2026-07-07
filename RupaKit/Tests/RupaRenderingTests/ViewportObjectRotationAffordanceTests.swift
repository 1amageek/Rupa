import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@Test func rotationAffordanceFollowsCursorAroundZAxis() {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let state = ViewportObjectEditState(
        xMin: -0.005,
        xMax: 0.005,
        yMin: 0.0,
        yMax: 0.01,
        zMin: -0.005,
        zMax: 0.005
    )
    let center = Point3D(x: 0.0, y: 0.005, z: 0.0)
    let projectedCenter = layout.project(center)
    let epsilon = 0.001
    let xDirection = screenDirection(
        from: projectedCenter,
        to: layout.project(Point3D(x: epsilon, y: 0.005, z: 0.0))
    )
    let yDirection = screenDirection(
        from: projectedCenter,
        to: layout.project(Point3D(x: 0.0, y: 0.005 + epsilon, z: 0.0))
    )
    let radius: CGFloat = 60.0
    let start = CGPoint(
        x: projectedCenter.x + xDirection.dx * radius,
        y: projectedCenter.y + xDirection.dy * radius
    )
    let current = CGPoint(
        x: projectedCenter.x + yDirection.dx * radius,
        y: projectedCenter.y + yDirection.dy * radius
    )

    let next = state.applying(
        action: .rotate(.z),
        start: start,
        current: current,
        layout: layout
    )

    // The cursor moved from the projected +X direction to the projected +Y
    // direction, a quarter turn following x -> y, so the object's x axis must
    // rotate onto +Y. The previous sign inversion rotated it onto -Y instead
    // (the object spun against the cursor).
    #expect(abs(Double(next.orientation.xAxis.y) - 1.0) < 1.0e-9)
    #expect(abs(Double(next.orientation.xAxis.x)) < 1.0e-9)
    #expect(abs(Double(next.orientation.yAxis.x) + 1.0) < 1.0e-9)
}

private func screenDirection(from start: CGPoint, to end: CGPoint) -> CGVector {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = (dx * dx + dy * dy).squareRoot()
    guard length > 0.0 else {
        return CGVector(dx: 0.0, dy: 0.0)
    }
    return CGVector(dx: dx / length, dy: dy / length)
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

@Test func profileCornerDragFollowsCursorWithoutCrossBleed() {
    // Dragging exactly along the projected x axis must not move the corner in
    // z: the former independent per-axis projections cross-bled on the
    // non-orthogonal isometric screen axes and the corner drifted off-cursor.
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.01, y: -0.01, width: 0.02, height: 0.02),
        size: CGSize(width: 800.0, height: 600.0)
    )
    let state = ViewportObjectEditState(
        xMin: -0.005,
        xMax: 0.005,
        yMin: 0.0,
        yMax: 0.01,
        zMin: -0.005,
        zMax: 0.005
    )
    let origin = layout.project(Point3D(x: 0.0, y: 0.0, z: 0.0))
    let alongX = layout.project(Point3D(x: 0.002, y: 0.0, z: 0.0))
    let alongZ = layout.project(Point3D(x: 0.0, y: 0.0, z: 0.003))

    let xDelta = state.profileCornerDragDelta(start: origin, current: alongX, layout: layout)
    let zDelta = state.profileCornerDragDelta(start: origin, current: alongZ, layout: layout)

    #expect(abs(Double(xDelta.x) - 0.002) < 1.0e-9)
    #expect(abs(Double(xDelta.y)) < 1.0e-9)
    #expect(abs(Double(zDelta.y) - 0.003) < 1.0e-9)
    #expect(abs(Double(zDelta.x)) < 1.0e-9)
}
