import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func joinSketchCurves(
        target: SelectionTarget,
        adjacentTarget: SelectionTarget,
        continuity: SketchCurveJoinContinuity = .g0,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let targetSelection = try editableSketchEntityBase(
            for: target,
            operationName: "Join Curves target"
        )
        let adjacentSelection = try editableSketchEntityBase(
            for: adjacentTarget,
            operationName: "Join Curves adjacent"
        )
        if case .line = targetSelection.entity,
           case .line = adjacentSelection.entity {
            try joinSketchLinePair(
                target: target,
                targetSelection: targetSelection,
                adjacentTarget: adjacentTarget,
                adjacentSelection: adjacentSelection,
                continuity: continuity,
                objectRegistry: objectRegistry
            )
            return
        }
        try joinSketchCurveGroup(
            target: target,
            targetSelection: targetSelection,
            adjacentTarget: adjacentTarget,
            adjacentSelection: adjacentSelection,
            continuity: continuity,
            objectRegistry: objectRegistry
        )
    }

    private mutating func joinSketchLinePair(
        target: SelectionTarget,
        targetSelection: EditableSketchEntitySelection,
        adjacentTarget: SelectionTarget,
        adjacentSelection: EditableSketchEntitySelection,
        continuity: SketchCurveJoinContinuity,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard continuity != .g2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves G2 continuity currently requires two spline endpoints."
            )
        }
        let join = try sketchLineJoinPlan(
            target: target,
            targetSelection: targetSelection,
            adjacentTarget: adjacentTarget,
            adjacentSelection: adjacentSelection
        )
        try validateSketchLineJoin(
            join,
            sketch: targetSelection.sketch,
            featureID: targetSelection.featureID
        )

        var feature = targetSelection.feature
        var sketch = targetSelection.sketch
        let constraintsBeforeJoin = sketch.constraints
        let dimensionsBeforeJoin = sketch.dimensions
        sketch.entities[join.retainedEntityID] = .line(join.retainedLine)
        sketch.entities.removeValue(forKey: join.removedEntityID)
        sketch.constraints = try constraintsAfterSketchLineJoin(
            sketch.constraints,
            join: join
        )
        sketch.dimensions = try dimensionsAfterSketchLineJoin(
            sketch.dimensions,
            join: join
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitJoin = false
        defer {
            if didCommitJoin == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        let joinedSource = JoinedCurveSource(
            featureID: targetSelection.featureID,
            retainedEntityID: join.retainedEntityID,
            restoredEntityID: join.removedEntityID,
            retainedOriginalLine: join.retainedOriginalLine,
            restoredOriginalLine: join.restoredOriginalLine,
            joinedLine: join.retainedLine,
            retainedSharedReference: join.retainedSharedReference,
            restoredSharedReference: join.removedSharedReference,
            restoredOuterReference: join.removedOuterReference,
            migratedRestoredOuterReference: join.migratedRemovedOuterReference,
            constraintsBeforeJoin: constraintsBeforeJoin,
            dimensionsBeforeJoin: dimensionsBeforeJoin,
            constraintsAfterJoin: sketch.constraints,
            dimensionsAfterJoin: sketch.dimensions
        )
        productMetadata.joinedCurveSources[joinedSource.id] = joinedSource
        if targetSelection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: targetSelection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: targetSelection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Join Curves"
        )
        didCommitJoin = true
    }

    private mutating func joinSketchCurveGroup(
        target: SelectionTarget,
        targetSelection: EditableSketchEntitySelection,
        adjacentTarget: SelectionTarget,
        adjacentSelection: EditableSketchEntitySelection,
        continuity: SketchCurveJoinContinuity,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let join = try sketchCurveGroupJoinPlan(
            target: target,
            targetSelection: targetSelection,
            adjacentTarget: adjacentTarget,
            adjacentSelection: adjacentSelection,
            continuity: continuity
        )
        try validateSketchCurveGroupJoin(
            join,
            sketch: targetSelection.sketch,
            featureID: targetSelection.featureID
        )

        var feature = targetSelection.feature
        var sketch = targetSelection.sketch
        let constraintsBeforeJoin = sketch.constraints
        let dimensionsBeforeJoin = sketch.dimensions
        _ = try applySketchCurveGroupJoinConstraints(to: &sketch, join: join)

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitJoin = false
        defer {
            if didCommitJoin == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        let joinedSource = JoinedCurveGroupSource(
            featureID: targetSelection.featureID,
            memberEntityIDs: join.memberEntityIDs,
            firstJoinedReference: join.firstJoinedReference,
            secondJoinedReference: join.secondJoinedReference,
            continuity: join.continuity,
            constraintsBeforeJoin: constraintsBeforeJoin,
            dimensionsBeforeJoin: dimensionsBeforeJoin,
            constraintsAfterJoin: sketch.constraints,
            dimensionsAfterJoin: sketch.dimensions
        )
        productMetadata.joinedCurveGroupSources[joinedSource.id] = joinedSource
        try commitSketchEntityEdit(
            featureID: targetSelection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Join Curves"
        )
        didCommitJoin = true
    }

    public mutating func unjoinSketchCurve(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntityBase(
            for: target,
            operationName: "Unjoin Curve"
        )
        if let source = try joinedCurveSourceIfPresent(for: selection) {
            try unjoinSketchLinePair(
                source,
                selection: selection,
                objectRegistry: objectRegistry
            )
            return
        }
        if let source = try joinedCurveGroupSourceIfPresent(for: selection) {
            try unjoinSketchCurveGroup(
                source,
                selection: selection,
                objectRegistry: objectRegistry
            )
            return
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Unjoin Curve requires a source curve retained by a prior Join Curves operation."
        )
    }

    private mutating func unjoinSketchLinePair(
        _ source: JoinedCurveSource,
        selection: EditableSketchEntitySelection,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard case .line(let currentLine) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve currently supports retained source line targets from Join Curves."
            )
        }
        try validateSketchLineUnjoin(
            source,
            currentLine: currentLine,
            sketch: selection.sketch
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[source.retainedEntityID] = .line(source.retainedOriginalLine)
        sketch.entities[source.restoredEntityID] = .line(source.restoredOriginalLine)
        sketch.constraints = source.constraintsBeforeJoin
        sketch.dimensions = source.dimensionsBeforeJoin

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitUnjoin = false
        defer {
            if didCommitUnjoin == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.joinedCurveSources.removeValue(forKey: source.id)
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Unjoin Curve"
        )
        didCommitUnjoin = true
    }

    private mutating func unjoinSketchCurveGroup(
        _ source: JoinedCurveGroupSource,
        selection: EditableSketchEntitySelection,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        try validateSketchCurveGroupUnjoin(
            source,
            sketch: selection.sketch
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.constraints = source.constraintsBeforeJoin
        sketch.dimensions = source.dimensionsBeforeJoin

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitUnjoin = false
        defer {
            if didCommitUnjoin == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.joinedCurveGroupSources.removeValue(forKey: source.id)
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Unjoin Curve"
        )
        didCommitUnjoin = true
    }
}
