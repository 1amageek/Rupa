import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func trimSketchCurveSegment(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve trim")
        try validateSketchCurveSegmentCanTrim(selection: selection)

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities.removeValue(forKey: selection.entityID)
        sketch.constraints = constraintsAfterSketchCurveTrim(
            sketch.constraints,
            trimmedEntityID: selection.entityID
        )
        sketch.dimensions = dimensionsAfterSketchCurveTrim(
            sketch.dimensions,
            trimmedEntityID: selection.entityID
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitTrim = false
        defer {
            if didCommitTrim == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve trim"
        )
        didCommitTrim = true
    }

    private func validateSketchCurveSegmentCanTrim(
        selection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        )
    ) throws {
        switch selection.entity {
        case .line,
             .arc:
            break
        case .spline(let spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve trim requires an open spline segment."
                )
            }
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve trim requires a bounded curve segment; circles do not expose segment boundaries."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve trim requires a curve segment target."
            )
        }

        for source in productMetadata.bridgeCurveSources.values where source.featureID == selection.featureID {
            if source.entityID == selection.entityID {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve trim cannot remove a generated Bridge Curve source."
                )
            }
            if sketchReference(source.firstEndpoint.reference, references: selection.entityID) ||
                sketchReference(source.secondEndpoint.reference, references: selection.entityID) {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve trim cannot remove a segment used by Bridge Curve metadata."
                )
            }
        }
    }

    private func constraintsAfterSketchCurveTrim(
        _ constraints: [SketchConstraint],
        trimmedEntityID: SketchEntityID
    ) -> [SketchConstraint] {
        constraints.filter { constraint in
            sketchConstraint(constraint, references: trimmedEntityID) == false
        }
    }

    private func dimensionsAfterSketchCurveTrim(
        _ dimensions: [SketchDimension],
        trimmedEntityID: SketchEntityID
    ) -> [SketchDimension] {
        dimensions.filter { dimension in
            sketchDimension(dimension, references: trimmedEntityID) == false
        }
    }
}
