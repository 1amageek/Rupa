import RupaCore
import RupaRendering
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceCanvasPlaneInputMapperPreservesStandardPlaneFootprintInput() throws {
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let point = Point2D(x: 0.12, y: -0.04)

    let result = try mapper.map(
        modelPoint: point,
        modelWorldPoint: nil,
        sketchPlane: .zx
    )

    #expect(result.point == point)
    #expect(result.worldPoint == nil)
}

@Test func workspaceCanvasPlaneInputMapperIntersectsCustomPlaneFromViewRay() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 0.0, y: 0.2, z: 0.0),
            normal: .unitY
        )
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))

    let result = try mapper.map(
        modelPoint: Point2D(x: 0.04, y: 0.03),
        modelWorldPoint: nil,
        sketchPlane: plane
    )

    let worldPoint = try #require(result.worldPoint)
    let depth = offsetVector(from: coordinateSystem.origin, to: worldPoint).dot(coordinateSystem.normal)
    #expect(abs(depth) <= 1.0e-9)
    #expect(pointIsApproximatelyEqual(result.point, coordinateSystem.project(worldPoint).point))
}

@Test func workspaceCanvasPlaneInputMapperProjectsKnownWorldPointOntoCustomPlane() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 0.0, y: 0.2, z: 0.0),
            normal: .unitY
        )
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: plane)
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))
    let worldPoint = Point3D(x: 0.03, y: 0.2, z: -0.08)

    let result = try mapper.map(
        modelPoint: Point2D(x: 10.0, y: 10.0),
        modelWorldPoint: worldPoint,
        sketchPlane: plane
    )

    #expect(result.worldPoint == worldPoint)
    #expect(pointIsApproximatelyEqual(result.point, coordinateSystem.project(worldPoint).point))
}

@Test func workspaceCanvasPlaneInputMapperRejectsCustomPlaneParallelToViewRay() throws {
    let plane = SketchPlane.plane(
        Plane3D(
            origin: .origin,
            normal: .unitX
        )
    )
    let mapper = WorkspaceCanvasPlaneInputMapper(projectionBasis: .axisFront(.z))

    do {
        _ = try mapper.map(
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: plane
        )
        Issue.record("Expected mapper to reject a custom plane parallel to the view ray.")
    } catch let failure as WorkspaceCanvasPlaneInputMapper.Failure {
        #expect(failure == .viewRayParallelToPlane)
    }
}

private func pointIsApproximatelyEqual(
    _ lhs: Point2D,
    _ rhs: Point2D,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

private func offsetVector(from start: Point3D, to end: Point3D) -> Vector3D {
    Vector3D(
        x: end.x - start.x,
        y: end.y - start.y,
        z: end.z - start.z
    )
}
