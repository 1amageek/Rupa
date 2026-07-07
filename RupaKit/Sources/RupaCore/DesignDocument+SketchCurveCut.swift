import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func cutSketchCurve(
        target: SelectionTarget,
        cutter: SelectionTarget,
        options: CutCurveOptions = CutCurveOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [SketchEntityID] {
        let targetSelection = try editableSketchEntity(for: target, operationName: "Cut Curve target")
        let cutterSelection = try editableSketchEntity(for: cutter, operationName: "Cut Curve cutter")
        if case .circle = targetSelection.entity {
            return try cutSketchCircleTarget(
                targetSelection: targetSelection,
                cutterSelection: cutterSelection,
                options: options,
                objectRegistry: objectRegistry
            )
        }
        let fractions = try cutSketchCurveFractions(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        let localFractions = try sequentialCutCurveLocalFractions(
            fractions: fractions,
            entity: targetSelection.entity
        )
        var createdEntityIDs: [SketchEntityID] = []
        var remainingTarget = target
        for localFraction in localFractions {
            let createdEntityID = try splitSketchCurve(
                target: remainingTarget,
                fraction: .scalar(localFraction),
                objectRegistry: objectRegistry
            )
            createdEntityIDs.append(createdEntityID)
            remainingTarget = SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(
                    SelectionComponentID.sketchEntity(
                        featureID: targetSelection.featureID,
                        entityID: createdEntityID
                    )
                )
            )
        }
        return createdEntityIDs
    }

    private func sequentialCutCurveLocalFractions(
        fractions: [Double],
        entity: SketchEntity
    ) throws -> [Double] {
        switch entity {
        case .spline(let spline):
            return try sequentialSplineCutCurveLocalFractions(
                fractions: fractions,
                controlPointCount: spline.controlPoints.count
            )
        case .line, .arc, .circle, .point:
            return try sequentialLinearCutCurveLocalFractions(fractions: fractions)
        }
    }

    private func sequentialLinearCutCurveLocalFractions(
        fractions: [Double]
    ) throws -> [Double] {
        var localFractions: [Double] = []
        var previousFraction = 0.0
        for fraction in fractions {
            let denominator = 1.0 - previousFraction
            guard denominator > 1.0e-12 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve intersection sequence collapsed the remaining target segment."
                )
            }
            localFractions.append((fraction - previousFraction) / denominator)
            previousFraction = fraction
        }
        return localFractions
    }

    /// Converts sorted global cut fractions on the ORIGINAL spline into the
    /// local fraction each sequential splitSketchCurve call must receive.
    ///
    /// A spline's global parameter is uniform per Bezier segment
    /// ((segmentIndex + local) / segmentCount, see SketchCurveSampler), and
    /// splitSpline keeps the remainder's trailing segments subdivided while the
    /// split segment's tail collapses into a single renormalized segment. The
    /// remap therefore has to be evaluated per segment instead of linearly, or
    /// every cut after the first lands off the cutter.
    private func sequentialSplineCutCurveLocalFractions(
        fractions: [Double],
        controlPointCount: Int
    ) throws -> [Double] {
        guard controlPointCount >= 4,
              (controlPointCount - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve target requires a cubic Bezier spline."
            )
        }
        let segmentCount = (controlPointCount - 1) / 3
        let knotTolerance = 1.0e-9
        var remainderStartSegment = 0
        var remainderStartLocal = 0.0
        var localFractions: [Double] = []
        for fraction in fractions {
            let scaled = fraction * Double(segmentCount)
            let segmentIndex = min(Int(floor(scaled)), segmentCount - 1)
            let segmentLocal = scaled - Double(segmentIndex)
            let remainderSegmentCount = segmentCount - remainderStartSegment
            guard remainderSegmentCount > 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve intersection sequence collapsed the remaining target segment."
                )
            }
            let remainderSegmentIndex: Int
            let remainderSegmentLocal: Double
            if segmentIndex <= remainderStartSegment {
                guard segmentIndex == remainderStartSegment,
                      segmentLocal > remainderStartLocal else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Cut Curve intersection sequence collapsed the remaining target segment."
                    )
                }
                let denominator = 1.0 - remainderStartLocal
                guard denominator > 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Cut Curve intersection sequence collapsed the remaining target segment."
                    )
                }
                remainderSegmentIndex = 0
                remainderSegmentLocal = (segmentLocal - remainderStartLocal) / denominator
            } else {
                remainderSegmentIndex = segmentIndex - remainderStartSegment
                remainderSegmentLocal = segmentLocal
            }
            localFractions.append(
                (Double(remainderSegmentIndex) + remainderSegmentLocal) /
                    Double(remainderSegmentCount)
            )
            // Mirror splitSpline's knot snapping so the tracked remainder start
            // matches the spline splitSketchCurve actually produces next.
            if remainderSegmentLocal <= knotTolerance {
                remainderStartSegment += remainderSegmentIndex
                remainderStartLocal = 0.0
            } else if remainderSegmentLocal >= 1.0 - knotTolerance {
                remainderStartSegment += remainderSegmentIndex + 1
                remainderStartLocal = 0.0
            } else {
                remainderStartSegment = segmentIndex
                remainderStartLocal = segmentLocal
            }
        }
        return localFractions
    }

    private mutating func cutSketchCircleTarget(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions,
        objectRegistry: ObjectTypeRegistry
    ) throws -> [SketchEntityID] {
        try validateCutSketchCurveSelections(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        guard case .circle(let targetCircleEntity) = targetSelection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target requires a source circle target."
            )
        }
        try validateSketchCircleCanCut(selection: targetSelection)
        let targetCircle = try resolvedCutCurveCircle(
            targetCircleEntity,
            owner: "Cut Curve target"
        )
        let angles = try cutAnglesForCircleTarget(
            target: targetCircle,
            cutterSelection: cutterSelection,
            extendsCutter: options.extendsCutter
        )

        let retainedArc = SketchArc(
            center: targetCircleEntity.center,
            radius: targetCircleEntity.radius,
            startAngle: .angle(angles[0], .radian),
            endAngle: .angle(angles[1], .radian)
        )
        let newArc = SketchArc(
            center: targetCircleEntity.center,
            radius: targetCircleEntity.radius,
            startAngle: .angle(angles[1], .radian),
            endAngle: .angle(angles[0], .radian)
        )
        try validateArc(retainedArc, owner: "Cut Curve retained circle arc")
        try validateArc(newArc, owner: "Cut Curve new circle arc")

        let newEntityID = SketchEntityID()
        var feature = targetSelection.feature
        var sketch = targetSelection.sketch
        sketch.entities[targetSelection.entityID] = .arc(retainedArc)
        sketch.entities[newEntityID] = .arc(newArc)
        sketch.constraints.append(.coincident(.arcEnd(targetSelection.entityID), .arcStart(newEntityID)))
        sketch.constraints.append(.coincident(.arcEnd(newEntityID), .arcStart(targetSelection.entityID)))

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitCut = false
        defer {
            if didCommitCut == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if targetSelection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: targetSelection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: targetSelection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Cut Curve"
        )
        didCommitCut = true
        return [newEntityID]
    }

    private func validateSketchCircleCanCut(
        selection: EditableSketchEntitySelection
    ) throws {
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cannot cut a generated Bridge Curve source."
            )
        }
        let affectedEntityIDs: Set<SketchEntityID> = [selection.entityID]
        for dimension in selection.sketch.dimensions where dimensionReferencesAny(
            dimension,
            entityIDs: affectedEntityIDs
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target cannot preserve dimensions attached to the circle yet."
            )
        }
        for constraint in selection.sketch.constraints where constraintReferencesAny(
            constraint,
            entityIDs: affectedEntityIDs
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target cannot preserve constraints attached to the circle yet."
            )
        }
    }
}
