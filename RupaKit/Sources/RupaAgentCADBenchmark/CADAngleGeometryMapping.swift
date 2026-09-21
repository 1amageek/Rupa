import Foundation
import RupaCore
import SwiftCAD

/// Owns angle world/local mapping at the production boundary.
enum CADAngleGeometryMapping {
    static func sourcePlane(
        orientation: CADSketchPlane,
        intersection: CADPoint3D,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        try intersection.validate(caseID: caseID, field: "angle.intersection")
        let world = intersection.meters
        let plane = SketchPlane.plane(
            Plane3D(
                origin: Point3D(x: world.x, y: world.y, z: world.z),
                normal: normal(for: orientation)
            )
        )
        _ = try SketchPlaneCoordinateSystem(
            plane: plane,
            tolerance: modelingTolerance.distance
        )
        return plane
    }

    static func localPoint(
        from point: CADPoint3D,
        sourcePlane: SketchPlane,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID,
        field: String
    ) throws -> Point2D {
        try point.validate(caseID: caseID, field: field)
        let coordinateSystem = try SketchPlaneCoordinateSystem(
            plane: sourcePlane,
            tolerance: modelingTolerance.distance
        )
        let world = point.meters
        let projection = coordinateSystem.project(
            Point3D(x: world.x, y: world.y, z: world.z)
        )
        guard projection.point.x.isFinite,
              projection.point.y.isFinite,
              projection.depth.isFinite,
              abs(projection.depth) <= modelingTolerance.distance else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "\(field) is outside the declared angle plane."
            )
        }
        return projection.point
    }

    static func worldPoint(
        from localPoint: SketchEntitySummaryResult.Point,
        sourcePlane: SketchPlane,
        modelingTolerance: ModelingTolerance
    ) throws -> Point3D {
        let coordinateSystem = try SketchPlaneCoordinateSystem(
            plane: sourcePlane,
            tolerance: modelingTolerance.distance
        )
        return coordinateSystem.point(from: Point2D(x: localPoint.x, y: localPoint.y))
    }

    static func normal(for orientation: CADSketchPlane) -> Vector3D {
        switch orientation {
        case .xy: .unitZ
        case .xz: .unitY
        case .yz: .unitX
        }
    }
}
