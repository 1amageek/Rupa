import RupaCore
import SwiftCAD

/// Maps a submitted cylinder base center and axis to the production sketch plane.
enum CADCylinderGeometryMapping {
    struct CommandGeometry: Sendable {
        let plane: SketchPlane
        let localCenter: SketchPoint
        let normalizedAxis: CADDirection3D
    }

    static func commandGeometry(
        baseCenter: CADPoint3D,
        axis: CADDirection3D,
        caseID: CADBenchmarkCaseID
    ) throws -> CommandGeometry {
        try baseCenter.validate(caseID: caseID, field: "cylinder.submittedBaseCenter")
        try axis.validate(caseID: caseID, field: "cylinder.submittedAxis")
        let length = axis.length
        guard length.isFinite, length > 0 else {
            throw CADBenchmarkError.invalidDirection(
                caseID: caseID.rawValue,
                field: "cylinder.submittedAxis"
            )
        }
        let normalized = CADDirection3D(
            x: axis.x / length,
            y: axis.y / length,
            z: axis.z / length
        )
        let point = baseCenter.meters
        return CommandGeometry(
            plane: .plane(Plane3D(
                origin: Point3D(x: point.x, y: point.y, z: point.z),
                normal: Vector3D(x: normalized.x, y: normalized.y, z: normalized.z)
            )),
            localCenter: SketchPoint(
                x: .length(0, .meter),
                y: .length(0, .meter)
            ),
            normalizedAxis: normalized
        )
    }
}
