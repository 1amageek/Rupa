import Foundation
import RupaCore
import SwiftCAD

/// Owns circle center and affine-plane mapping at the production boundary.
enum CADCircleGeometryMapping {
    static func sourcePlane(
        orientation: CADSketchPlane,
        targetCenter: CADPoint3D,
        submittedCenter: CADPoint3D,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        try targetCenter.validate(caseID: caseID, field: "circle.targetCenter")
        try submittedCenter.validate(caseID: caseID, field: "circle.submittedCenter")
        let target = targetCenter.meters
        let submitted = submittedCenter.meters
        let normal = normal(for: orientation)
        let displacement = Vector3D(
            x: submitted.x - target.x,
            y: submitted.y - target.y,
            z: submitted.z - target.z
        )
        guard abs(displacement.dot(normal)) <= modelingTolerance.distance else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The submitted circle center is outside the declared affine plane."
            )
        }
        return .plane(
            Plane3D(
                origin: Point3D(x: target.x, y: target.y, z: target.z),
                normal: normal
            )
        )
    }

    static func localPoint(
        from worldPoint: CADPoint3D,
        sourcePlane: SketchPlane,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> Point2D {
        try worldPoint.validate(caseID: caseID, field: "circle.submittedCenter")
        let coordinateSystem = try SketchPlaneCoordinateSystem(
            plane: sourcePlane,
            tolerance: modelingTolerance.distance
        )
        let point = worldPoint.meters
        let projection = coordinateSystem.project(
            Point3D(x: point.x, y: point.y, z: point.z)
        )
        guard abs(projection.depth) <= modelingTolerance.distance else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The submitted circle center is outside the declared affine plane."
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
