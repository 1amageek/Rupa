import Foundation
import RupaCore
import SwiftCAD

/// Maps a lower-corner box specification to the centered rectangle production command.
enum CADBoxGeometryMapping {
    static func bottomCenter(
        origin: CADPoint3D,
        width: CADLength,
        depth: CADLength
    ) -> CADPoint3D {
        let point = origin.meters
        return CADPoint3D(
            x: point.x + width.meters / 2.0,
            y: point.y + depth.meters / 2.0,
            z: point.z,
            unit: .meter
        )
    }

    static func sourcePlane(
        submittedOrigin: CADPoint3D,
        submittedWidth: CADLength,
        submittedDepth: CADLength,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        let submittedCenter = bottomCenter(
            origin: submittedOrigin,
            width: submittedWidth,
            depth: submittedDepth
        )
        try submittedCenter.validate(caseID: caseID, field: "box.submittedBottomCenter")
        return .plane(
            Plane3D(
                origin: Point3D(
                    x: submittedCenter.meters.x,
                    y: submittedCenter.meters.y,
                    z: submittedCenter.meters.z
                ),
                normal: .unitZ
            )
        )
    }
}
