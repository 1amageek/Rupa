import Foundation
import SwiftCAD

/// Owns transform composition for transform-case oracle evaluation.
enum CADTransformGeometryMapping {
    static func localTransform(
        submission: CADTransformSubmission,
        caseID: CADBenchmarkCaseID
    ) throws -> Transform3D {
        try submission.validate(caseID: caseID)
        let axisLength = submission.rotationAxis.length
        guard axisLength.isFinite, axisLength > 0 else {
            throw CADBenchmarkError.invalidDirection(
                caseID: caseID.rawValue,
                field: "transform.rotationAxis"
            )
        }
        let x = submission.rotationAxis.x / axisLength
        let y = submission.rotationAxis.y / axisLength
        let z = submission.rotationAxis.z / axisLength
        let angle = submission.rotation.radians
        let cosine = cos(angle)
        let sine = sin(angle)
        let oneMinusCosine = 1.0 - cosine
        let rotation = [
            cosine + x * x * oneMinusCosine,
            x * y * oneMinusCosine - z * sine,
            x * z * oneMinusCosine + y * sine,
            y * x * oneMinusCosine + z * sine,
            cosine + y * y * oneMinusCosine,
            y * z * oneMinusCosine - x * sine,
            z * x * oneMinusCosine - y * sine,
            z * y * oneMinusCosine + x * sine,
            cosine + z * z * oneMinusCosine,
        ]
        let pivot = submission.axisPoint.meters
        let translation = submission.translation.meters
        let rotatedPivot = (
            x: rotation[0] * pivot.x + rotation[1] * pivot.y + rotation[2] * pivot.z,
            y: rotation[3] * pivot.x + rotation[4] * pivot.y + rotation[5] * pivot.z,
            z: rotation[6] * pivot.x + rotation[7] * pivot.y + rotation[8] * pivot.z
        )
        let offset = (
            x: translation.x + pivot.x - rotatedPivot.x,
            y: translation.y + pivot.y - rotatedPivot.y,
            z: translation.z + pivot.z - rotatedPivot.z
        )
        return Transform3D(matrix: try Matrix4x4(values: [
            rotation[0], rotation[1], rotation[2], offset.x,
            rotation[3], rotation[4], rotation[5], offset.y,
            rotation[6], rotation[7], rotation[8], offset.z,
            0, 0, 0, 1,
        ]))
    }

}
