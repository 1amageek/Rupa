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
        expectedOrigin: CADPoint3D,
        expectedWidth: CADLength,
        expectedDepth: CADLength,
        submittedOrigin: CADPoint3D,
        submittedWidth: CADLength,
        submittedDepth: CADLength,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        let expectedCenter = bottomCenter(
            origin: expectedOrigin,
            width: expectedWidth,
            depth: expectedDepth
        )
        let submittedCenter = bottomCenter(
            origin: submittedOrigin,
            width: submittedWidth,
            depth: submittedDepth
        )
        return try CADRectangleGeometryMapping.sourcePlane(
            orientation: .xy,
            targetCenter: expectedCenter,
            submittedCenter: submittedCenter,
            modelingTolerance: modelingTolerance,
            caseID: caseID
        )
    }
}
