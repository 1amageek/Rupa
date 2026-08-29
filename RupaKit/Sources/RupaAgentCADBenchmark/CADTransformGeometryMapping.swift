import Foundation
import RupaCore
import SwiftCAD

/// Owns transform composition and public-source seeding for transform cases.
enum CADTransformGeometryMapping {
    struct Seed: Sendable {
        let document: DesignDocument
        let sceneNodeID: SceneNodeID
        let sourceAction: CADCandidateAction
    }

    @MainActor
    static func seed(
        projection: CADTransformChallengeProjection
    ) throws -> Seed {
        var document = DesignDocument.empty(named: projection.id.rawValue)
        let tolerance = document.modelingSettings.tolerance
        let featureID: FeatureID
        let sourceAction: CADCandidateAction
        switch projection.source {
        case .line(let source):
            let plane = try CADLineGeometryMapping.sourcePlane(
                orientation: source.orientation,
                anchor: source.anchor,
                modelingTolerance: tolerance,
                caseID: projection.id
            )
            let start = try CADLineGeometryMapping.projection(
                of: source.start,
                sourcePlane: plane,
                modelingTolerance: tolerance,
                caseID: projection.id,
                field: "transform.source.line.start"
            )
            let end = try CADLineGeometryMapping.projection(
                of: source.end,
                sourcePlane: plane,
                modelingTolerance: tolerance,
                caseID: projection.id,
                field: "transform.source.line.end"
            )
            featureID = try document.createLineSketch(
                name: "\(projection.id.rawValue).source",
                plane: plane,
                start: sketchPoint(start.point),
                end: sketchPoint(end.point)
            )
            sourceAction = .automation(.sketch(.line(
                name: "\(projection.id.rawValue).source",
                plane: source.orientation,
                start: source.start,
                end: source.end
            )))
        case .rectangle(let source):
            let plane = try CADRectangleGeometryMapping.sourcePlane(
                orientation: source.orientation,
                targetCenter: source.center,
                submittedCenter: source.center,
                modelingTolerance: tolerance,
                caseID: projection.id
            )
            featureID = try document.createRectangleSketch(
                name: "\(projection.id.rawValue).source",
                plane: plane,
                width: length(source.width.meters),
                height: length(source.height.meters)
            )
            sourceAction = .automation(.sketch(.rectangle(
                name: "\(projection.id.rawValue).source",
                plane: source.orientation,
                center: source.center,
                width: source.width,
                height: source.height
            )))
        case .circle(let source):
            let plane = try CADCircleGeometryMapping.sourcePlane(
                orientation: source.orientation,
                targetCenter: source.center,
                submittedCenter: source.center,
                modelingTolerance: tolerance,
                caseID: projection.id
            )
            featureID = try document.createCircleSketch(
                name: "\(projection.id.rawValue).source",
                plane: plane,
                center: SketchPoint(x: length(0), y: length(0)),
                radius: length(source.radius.meters)
            )
            sourceAction = .automation(.sketch(.circle(
                name: "\(projection.id.rawValue).source",
                plane: source.orientation,
                center: source.center,
                radius: source.radius
            )))
        case .box(let source):
            let plane = try CADBoxGeometryMapping.sourcePlane(
                submittedOrigin: source.origin,
                submittedWidth: source.width,
                submittedDepth: source.depth,
                caseID: projection.id
            )
            featureID = try document.createExtrudedRectangle(
                name: "\(projection.id.rawValue).source",
                plane: plane,
                width: length(source.width.meters),
                height: length(source.depth.meters),
                depth: length(source.height.meters),
                direction: .normal
            )
            sourceAction = .automation(.solid(.box(
                name: "\(projection.id.rawValue).source",
                origin: source.origin,
                width: source.width,
                depth: source.depth,
                height: source.height
            )))
        case .cylinder(let source):
            let geometry = try CADCylinderGeometryMapping.commandGeometry(
                baseCenter: source.baseCenter,
                axis: source.axis,
                caseID: projection.id
            )
            featureID = try document.createExtrudedCircle(
                name: "\(projection.id.rawValue).source",
                plane: geometry.plane,
                center: geometry.localCenter,
                radius: length(source.radius.meters),
                depth: length(source.depth.meters),
                direction: .normal
            )
            sourceAction = .automation(.solid(.cylinder(
                name: "\(projection.id.rawValue).source",
                baseCenter: source.baseCenter,
                axis: source.axis,
                radius: source.radius,
                depth: source.depth
            )))
        }
        guard let sceneNodeID = document.productMetadata.sceneNodes.values.first(where: {
            $0.reference == .sketch(featureID) || $0.reference == .body(featureID)
        })?.id else {
            throw CADBenchmarkError.invalidInput(
                caseID: projection.id.rawValue,
                reason: "The public transform source produced no scene node."
            )
        }
        return Seed(
            document: document,
            sceneNodeID: sceneNodeID,
            sourceAction: sourceAction
        )
    }

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

    private static func length(_ meters: Double) -> CADExpression {
        .constant(.length(meters, unit: .meter))
    }

    private static func sketchPoint(_ point: Point2D) -> SketchPoint {
        SketchPoint(x: length(point.x), y: length(point.y))
    }
}
