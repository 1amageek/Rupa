import Foundation
import RupaCore
import SwiftCAD

/// Owns rectangle center and affine-plane mapping at the production boundary.
enum CADRectangleGeometryMapping {
    static func sourcePlane(
        orientation: CADSketchPlane,
        targetCenter: CADPoint3D,
        submittedCenter: CADPoint3D,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        try targetCenter.validate(caseID: caseID, field: "rectangle.targetCenter")
        try submittedCenter.validate(caseID: caseID, field: "rectangle.submittedCenter")
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
                reason: "The submitted rectangle center is outside the declared affine plane."
            )
        }
        return .plane(
            Plane3D(
                origin: Point3D(x: submitted.x, y: submitted.y, z: submitted.z),
                normal: normal
            )
        )
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
