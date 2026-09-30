import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func cutSketchCurve(
        target: SelectionTarget,
        cutter: SelectionTarget,
        options: CutCurveOptions = CutCurveOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [SketchEntityID] {
        if case .face = cutter.component {
            return try cutSketchCurve(
                target: target, byFace: cutter, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )
        }
        let (targetSelection, cutterSelection) = try placedCutSelections(target: target, cutter: cutter, options: options)
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
        var updated = self
        var createdEntityIDs: [SketchEntityID] = []
        var remainingTarget = target
        for localFraction in localFractions {
            let createdEntityID = try updated.splitSketchCurve(
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
        self = updated
        return createdEntityIDs
    }

    /// Cut Curve on several targets with several cutters: every target is cut wherever a cutter
    /// crosses it, each cutter cutting the pieces the earlier ones left. A target no cutter crosses
    /// fails the whole cut and the document is unchanged. Returns the entities the cuts created.
    @discardableResult
    public mutating func cutSketchCurves(
        targets: [SelectionTarget],
        cutters: [SelectionTarget],
        options: CutCurveOptions = CutCurveOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [SketchEntityID] {
        guard !targets.isEmpty, !cutters.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Cut Curve needs at least one target and one cutter.")
        }
        guard Set(targets).isDisjoint(with: Set(cutters)) else {
            throw EditorError(code: .commandInvalid, message: "Cut Curve takes a curve as a target or as a cutter, not both.")
        }
        var updated = self
        var created: [SketchEntityID] = []
        for target in targets {
            let featureID = try updated.editableSketchEntity(for: target, operationName: "Cut Curve target").featureID
            var pieces = [target]
            var wasCut = false
            for cutter in cutters {
                var next: [SelectionTarget] = []
                for piece in pieces {
                    next.append(piece)
                    // The evaluation describes this document only until the first cut changes it;
                    // later reads find it stale and evaluate the cut document instead.
                    guard try updated.cutCurveCrosses(
                        target: piece, cutter: cutter, options: options, objectRegistry: objectRegistry,
                        currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
                    ) else { continue }
                    let made = try updated.cutSketchCurve(
                        target: piece, cutter: cutter, options: options, objectRegistry: objectRegistry,
                        currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
                    )
                    wasCut = true
                    created += made
                    next += made.map {
                        SelectionTarget(
                            sceneNodeID: target.sceneNodeID,
                            component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: $0))
                        )
                    }
                }
                pieces = next
            }
            guard wasCut else {
                throw EditorError(code: .commandInvalid, message: "Cut Curve: a target curve is not crossed by any cutter.")
            }
        }
        self = updated
        return created
    }

    func sequentialCutCurveLocalFractions(
        fractions: [Double],
        entity: SketchEntity
    ) throws -> [Double] {
        switch entity {
        case .spline(let spline) where spline.isCubicBezierChain == false:
            // Any other degree or knots splits on its B-spline, whose parts' fractions are linear
            // in the original's.
            return try sequentialLinearCutCurveLocalFractions(fractions: fractions)
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
        let angles = try cutAnglesForCircleTarget(
            target: targetCircleEntity,
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

    func validateSketchCircleCanCut(
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

extension DesignDocument {
    /// Cut Curve with a face as the cutter: the target is split wherever it crosses the face,
    /// inside the face's trim (`faceCutFractions`).
    mutating func cutSketchCurve(
        target: SelectionTarget, byFace face: SelectionTarget, objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?, currentGeneration: DocumentGeneration?
    ) throws -> [SketchEntityID] {
        let selection = try editableSketchEntity(for: target, operationName: "Cut Curve target")
        let fractions = try faceCutFractions(
            target: target, face: face, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard !fractions.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Cut Curve: the face does not cross the target curve.")
        }
        let localFractions = try sequentialCutCurveLocalFractions(fractions: fractions, entity: selection.entity)
        var updated = self
        var created: [SketchEntityID] = []
        var remaining = target
        for localFraction in localFractions {
            let made = try updated.splitSketchCurve(target: remaining, fraction: .scalar(localFraction), objectRegistry: objectRegistry)
            created.append(made)
            remaining = SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(.sketchEntity(featureID: selection.featureID, entityID: made))
            )
        }
        self = updated
        return created
    }

    /// Where a line, arc or open spline target crosses a face, as sorted interior fractions: the
    /// target read in world space through its sketch's placement, its height along the face's
    /// outward normal (Swift-CAD's `FaceUVNChart`, in the face body's frame) sampled for sign
    /// changes and bisected, each crossing kept when it lies inside the face's trim.
    func faceCutFractions(
        target: SelectionTarget, face: SelectionTarget, objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?, currentGeneration: DocumentGeneration?
    ) throws -> [Double] {
        let owner = "Cut Curve"
        let selection = try editableSketchEntity(for: target, operationName: "\(owner) target")
        if case .circle = selection.entity {
            throw EditorError(code: .commandInvalid, message: "\(owner): a face cuts lines, arcs and open splines.")
        }
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        guard let evaluated = topology.evaluatedDocument,
              let entry = topology.entries.first(where: { $0.kind == .face && $0.selectionTarget() == face }),
              let reference = entry.stableReference else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) cutter face is not a face of an evaluated body.")
        }
        return try faceCrossingFractions(
            of: selection.entity,
            system: try placedSketchSystem(for: target, plane: selection.sketch.plane),
            face: SurfaceReference(subshape: reference),
            facePlacement: try worldPlacement(of: face.sceneNodeID),
            in: evaluated,
            owner: owner
        )
    }

    /// Where a sketch curve on the placed plane `system` crosses a face (its body placed by
    /// `facePlacement`) inside the face's trim, as sorted interior fractions (a spline's over its
    /// normalized knot domain).
    func faceCrossingFractions(
        of entity: SketchEntity,
        system: SketchPlaneCoordinateSystem,
        face surface: SurfaceReference,
        facePlacement: Transform3D,
        in evaluated: EvaluatedDocument,
        owner: String
    ) throws -> [Double] {
        let tolerance = modelingSettings.tolerance
        let source = try spatialSourceCurve(entity, system: system, owner: owner)
        let chart = try FaceUVNChart(face: surface, in: evaluated, tolerance: tolerance)
        let inverse = try facePlacement.inverse()
        let lower = source.breakpoints[0], upper = source.breakpoints[source.breakpoints.count - 1]
        func height(_ w: Double) throws -> Double {
            try chart.coordinate(of: try inverse.applied(to: try source.point(w))).n
        }
        let samples = 256
        var fractions: [Double] = []
        var previousW = lower
        var previousHeight = try height(lower)
        for index in 1...samples {
            let w = lower + (upper - lower) * Double(index) / Double(samples)
            let current = try height(w)
            if (previousHeight < 0) != (current < 0) {
                var a = previousW, b = w, heightA = previousHeight
                for _ in 0..<60 {
                    let middle = (a + b) / 2
                    let heightMiddle = try height(middle)
                    if (heightA < 0) == (heightMiddle < 0) { a = middle; heightA = heightMiddle } else { b = middle }
                }
                let crossing = (a + b) / 2
                let onFace = try SurfaceQueryEvaluator(tolerance: tolerance).closestPoint(
                    to: try inverse.applied(to: try source.point(crossing)), on: surface, in: evaluated
                )
                let fraction = (crossing - lower) / (upper - lower)
                if onFace.distance <= tolerance.distance * Self.spatialFitDeviationFactor, fraction > 1.0e-9, fraction < 1 - 1.0e-9 {
                    fractions.append(fraction)
                }
            }
            previousW = w
            previousHeight = current
        }
        return fractions
    }
}
