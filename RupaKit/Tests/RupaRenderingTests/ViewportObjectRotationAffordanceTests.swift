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
