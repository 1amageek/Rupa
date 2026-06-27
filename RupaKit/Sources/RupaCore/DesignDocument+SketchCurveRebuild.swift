import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func rebuildSketchCurve(
        target: SelectionTarget,
        options: CurveRebuildOptions,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> CurveRebuildReport {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve rebuild")
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild currently requires a spline entity target."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild currently requires an open spline curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild cannot edit a generated Bridge Curve source."
            )
        }

        let rebuilt: RebuiltSketchSpline
        switch options.method {
        case .points(let controlPointCount):
            rebuilt = try rebuiltSketchSplineByPointCount(
                spline,
                controlPointCount: controlPointCount,
                owner: "Sketch curve rebuild"
            )
        case .refit(let tolerance, let keepsCorners):
            rebuilt = try rebuiltSketchSplineByRefit(
                spline,
                tolerance: tolerance,
                keepsCorners: keepsCorners,
                owner: "Sketch curve rebuild"
            )
        case .explicitControl(let degree, let spanCount, let weight):
            rebuilt = try rebuiltSketchSplineByExplicitControl(
                spline,
                degree: degree,
                spanCount: spanCount,
                weight: weight,
                owner: "Sketch curve rebuild"
            )
        }

        let constraints = try constraintsAfterSketchCurveRebuild(
            selection.sketch.constraints,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )
        let dimensions = try dimensionsAfterSketchCurveRebuild(
            selection.sketch.dimensions,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )
        let bridgeCurveSources = try bridgeCurveSourcesAfterSketchCurveRebuild(
            productMetadata.bridgeCurveSources,
            featureID: selection.featureID,
            entityID: selection.entityID,
            rebuilt: rebuilt
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .spline(rebuilt.spline)
        sketch.constraints = constraints
        sketch.dimensions = dimensions

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitRebuild = false
        defer {
            if didCommitRebuild == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources = bridgeCurveSources
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve rebuild"
        )
        didCommitRebuild = true
        return CurveRebuildReport(
            sourceFeatureID: selection.featureID.description,
            entityID: selection.entityID.description,
            method: curveRebuildReportMethod(for: options),
            originalControlPointCount: rebuilt.originalControlPointCount,
            rebuiltControlPointCount: rebuilt.rebuiltControlPointCount,
            originalSpanCount: rebuilt.originalSegmentCount,
            rebuiltSpanCount: rebuilt.rebuiltSegmentCount,
            deviationMeasurement: .analyticCubicBezier,
            maximumDeviationMeters: rebuilt.deviation.maximumDistance,
            rootMeanSquareDeviationMeters: rebuilt.deviation.rootMeanSquareDistance,
            maximumDeviationFraction: rebuilt.deviation.maximumDistanceFraction,
            evaluatedIntervalCount: rebuilt.deviation.evaluatedIntervalCount,
            criticalPointCount: rebuilt.deviation.criticalPointCount
        )
    }

    private func curveRebuildReportMethod(
        for options: CurveRebuildOptions
    ) -> CurveRebuildReport.Method {
        switch options.method {
        case .points:
            return .points
        case .refit:
            return .refit
        case .explicitControl:
            return .explicitControl
        }
    }
}
