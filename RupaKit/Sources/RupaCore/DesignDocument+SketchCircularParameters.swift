import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setSketchCircleParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard center != nil || radius != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch circle parameter update requires a center or radius value."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch circle parameter update")
        guard case var .circle(circle) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch circle parameter update requires a circle entity target."
            )
        }
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        if center != nil {
            try pointPropagator.validateCanMove(
                .circleCenter(selection.entityID),
                in: selection.sketch,
                owner: "Sketch circle parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.validateCanResizeCircularEntity(
                selection.entityID,
                in: selection.sketch,
                owner: "Sketch circle parameter update"
            )
        }
        if let center {
            _ = try resolvedLengthValue(center.x, owner: "Sketch circle center x")
            _ = try resolvedLengthValue(center.y, owner: "Sketch circle center y")
            circle.center = center
        }
        if let radius {
            _ = try resolvedPositiveLengthValue(radius, owner: "Sketch circle radius")
            circle.radius = radius
        } else {
            _ = try resolvedPositiveLengthValue(circle.radius, owner: "Sketch circle radius")
        }

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .circle(circle)
        if center != nil {
            try pointPropagator.propagate(
                from: .circleCenter(selection.entityID),
                in: &sketch,
                owner: "Sketch circle parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.propagateCircularRadius(
                from: selection.entityID,
                in: &sketch,
                owner: "Sketch circle parameter update"
            )
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch circle parameter update"
        )
    }

    public mutating func setSketchArcParameters(
        target: SelectionTarget,
        center: SketchPoint?,
        radius: CADExpression?,
        startAngle: CADExpression?,
        endAngle: CADExpression?,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard center != nil || radius != nil || startAngle != nil || endAngle != nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch arc parameter update requires at least one value."
            )
        }

        let selection = try editableSketchEntity(for: target, operationName: "Sketch arc parameter update")
        guard case var .arc(arc) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch arc parameter update requires an arc entity target."
            )
        }
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        if center != nil {
            try pointPropagator.validateCanMove(
                .arcCenter(selection.entityID),
                in: selection.sketch,
                owner: "Sketch arc parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.validateCanResizeCircularEntity(
                selection.entityID,
                in: selection.sketch,
                owner: "Sketch arc parameter update"
            )
        }
        if let center {
            _ = try resolvedLengthValue(center.x, owner: "Sketch arc center x")
            _ = try resolvedLengthValue(center.y, owner: "Sketch arc center y")
            arc.center = center
        }
        if let radius {
            _ = try resolvedPositiveLengthValue(radius, owner: "Sketch arc radius")
            arc.radius = radius
        }
        if let startAngle {
            _ = try resolvedAngleValue(startAngle, owner: "Sketch arc start angle")
            arc.startAngle = startAngle
        }
        if let endAngle {
            _ = try resolvedAngleValue(endAngle, owner: "Sketch arc end angle")
            arc.endAngle = endAngle
        }
        try validateArc(arc, owner: "Sketch arc")

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .arc(arc)
        if center != nil {
            try pointPropagator.propagate(
                from: .arcCenter(selection.entityID),
                in: &sketch,
                owner: "Sketch arc parameter update"
            )
        }
        if radius != nil {
            try pointPropagator.propagateCircularRadius(
                from: selection.entityID,
                in: &sketch,
                owner: "Sketch arc parameter update"
            )
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch arc parameter update"
        )
    }
}
