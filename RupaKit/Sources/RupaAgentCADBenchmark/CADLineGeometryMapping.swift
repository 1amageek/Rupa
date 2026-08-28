import Foundation
import RupaCore
import SwiftCAD

/// Owns the line-category world/local mapping at the production boundary.
///
/// Public challenge values are world-space.  swift-CAD sketch points are
/// local to the selected source plane, so both route construction and oracle
/// observation use this one mapping contract.
enum CADLineGeometryMapping {
    static func sourcePlane(
        orientation: CADSketchPlane,
        anchor: CADPoint3D,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        try anchor.validate(caseID: caseID, field: "line.anchor")
        let worldAnchor = anchor.meters
        let normalDistance: Double
        let builtin: SketchPlane
        let normal: Vector3D
        switch orientation {
        case .xy:
            normalDistance = worldAnchor.z
            builtin = .xy
            normal = .unitZ
        case .xz:
            normalDistance = worldAnchor.y
            builtin = .zx
            normal = .unitY
        case .yz:
            normalDistance = worldAnchor.x
            builtin = .yz
            normal = .unitX
        }
        if abs(normalDistance) <= modelingTolerance.distance {
            return builtin
        }
        return .plane(
            Plane3D(
                origin: Point3D(x: worldAnchor.x, y: worldAnchor.y, z: worldAnchor.z),
                normal: normal
            )
        )
    }

    static func projection(
        of point: CADPoint3D,
        sourcePlane: SketchPlane,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID,
        field: String
    ) throws -> SketchPlaneCoordinateSystem.Projection {
        try point.validate(caseID: caseID, field: field)
        let coordinateSystem: SketchPlaneCoordinateSystem
        do {
            coordinateSystem = try SketchPlaneCoordinateSystem(
                plane: sourcePlane,
                tolerance: modelingTolerance.distance
            )
        } catch {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "The line source plane could not be constructed: \(error)."
            )
        }
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
                reason: "\(field) is outside the declared line plane."
            )
        }
        return projection
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
        return coordinateSystem.point(
            from: Point2D(x: localPoint.x, y: localPoint.y)
        )
    }
}
