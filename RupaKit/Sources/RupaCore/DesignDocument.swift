import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DesignDocument: Identifiable, Sendable {
    typealias EditableProfileRegionSelection = (
        featureID: FeatureID,
        profileIndex: Int,
        feature: FeatureNode,
        sketch: Sketch,
        profile: Profile
    )
    typealias PlannedOffsetRegionFeature = (
        name: String,
        result: OffsetRegionBuilder.Result
    )
    typealias EditableSketchEntitySelection = (
        featureID: FeatureID,
        entityID: SketchEntityID,
        feature: FeatureNode,
        sketch: Sketch,
        entity: SketchEntity
    )

    public var cadDocument: CADDocument
    public var displayUnit: LengthDisplayUnit
    public var ruler: RulerConfiguration
    public var productMetadata: ProductMetadata

    public var id: DocumentID {
        cadDocument.id
    }

    public init(
        cadDocument: CADDocument,
        displayUnit: LengthDisplayUnit,
        ruler: RulerConfiguration,
        productMetadata: ProductMetadata = .empty()
    ) {
        self.cadDocument = cadDocument
        self.displayUnit = displayUnit
        self.ruler = ruler
        self.productMetadata = productMetadata
    }

    public static func empty(named name: String = "Untitled") -> DesignDocument {
        let unit: LengthDisplayUnit = .millimeter
        return DesignDocument(
            cadDocument: CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: name)
            ),
            displayUnit: unit,
            ruler: .standard(for: unit),
            productMetadata: .empty()
        )
    }

    public mutating func reverseSketchCurve(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve reverse")
        let reversedEntity: SketchEntity
        let splineControlPointCount: Int?
        switch selection.entity {
        case .line(let line):
            let reversedLine = SketchLine(start: line.end, end: line.start)
            _ = try resolvedLineMetrics(reversedLine, owner: "Sketch curve reverse")
            reversedEntity = .line(reversedLine)
            splineControlPointCount = nil
        case .spline(var spline):
            spline.controlPoints = Array(spline.controlPoints.reversed())
            try validateSpline(spline, owner: "Sketch curve reverse")
            reversedEntity = .spline(spline)
            splineControlPointCount = spline.controlPoints.count
        case .arc:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse cannot reverse arc direction until arc source direction is represented."
            )
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse requires an open line or spline curve; circles do not expose direction."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve reverse requires a line or spline curve target."
            )
        }

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = reversedEntity
        sketch.constraints = constraintsAfterSketchCurveReverse(
            sketch.constraints,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )
        sketch.dimensions = dimensionsAfterSketchCurveReverse(
            sketch.dimensions,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitReverse = false
        defer {
            if didCommitReverse == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources = bridgeCurveSourcesAfterSketchCurveReverse(
            productMetadata.bridgeCurveSources,
            featureID: selection.featureID,
            entityID: selection.entityID,
            splineControlPointCount: splineControlPointCount
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve reverse"
        )
        didCommitReverse = true
    }

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

    public mutating func extendSketchCurve(
        target: SelectionTarget,
        distance: CADExpression,
        shape: ExtendCurveShape = .natural,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedDistance = try resolvedPositiveLengthValue(
            distance,
            owner: "Sketch curve extend distance"
        )
        let selection = try editableSketchEntityBase(
            for: target,
            operationName: "Sketch curve extend"
        )
        let endpoint = try extendCurveEndpoint(
            for: target,
            selection: selection,
            operationName: "Sketch curve extend"
        )
        try validateSketchCurveCanExtend(
            selection: selection,
            endpoint: endpoint,
            shape: shape
        )
        let extendedEntity = try extendedSketchCurveEntity(
            selection.entity,
            endpoint: endpoint,
            distance: distance,
            resolvedDistance: resolvedDistance,
            shape: shape,
            owner: "Sketch curve extend"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = extendedEntity

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitExtend = false
        defer {
            if didCommitExtend == false {
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
            errorOwner: "Sketch curve extend"
        )
        didCommitExtend = true
    }

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
                message: "Join Curves G2 continuity requires a source curve continuity solver that is not implemented yet."
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
        sketch.constraints = try constraintsAfterSketchCurveGroupJoin(
            sketch.constraints,
            join: join,
            sketch: sketch
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

    @discardableResult
    public mutating func splitSketchCurve(
        target: SelectionTarget,
        fraction: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let resolvedFraction = try resolvedScalarValue(fraction, owner: "Sketch curve split fraction")
        guard resolvedFraction > ModelingTolerance.standard.distance,
              resolvedFraction < 1.0 - ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split fraction must be greater than zero and less than one."
            )
        }
        let selection = try editableSketchEntity(for: target, operationName: "Sketch curve split")
        try validateSketchCurveCanSplit(selection: selection)

        let newEntityID = SketchEntityID()
        let split = try splitSketchCurveEntity(
            selection.entity,
            entityID: selection.entityID,
            newEntityID: newEntityID,
            fraction: resolvedFraction,
            owner: "Sketch curve split"
        )

        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = split.retainedEntity
        sketch.entities[newEntityID] = split.newEntity
        sketch.constraints = constraintsAfterSketchCurveSplit(
            sketch.constraints,
            split: split
        )
        sketch.dimensions = dimensionsAfterSketchCurveSplit(
            sketch.dimensions,
            split: split
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSplit = false
        defer {
            if didCommitSplit == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        productMetadata.bridgeCurveSources = try bridgeCurveSourcesAfterSketchCurveSplit(
            productMetadata.bridgeCurveSources,
            split: split
        )
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch curve split"
        )
        didCommitSplit = true
        return newEntityID
    }

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
        var createdEntityIDs: [SketchEntityID] = []
        var remainingTarget = target
        var previousFraction = 0.0
        for fraction in fractions {
            let denominator = 1.0 - previousFraction
            guard denominator > 1.0e-12 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve intersection sequence collapsed the remaining target segment."
                )
            }
            let localFraction = (fraction - previousFraction) / denominator
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
            previousFraction = fraction
        }
        return createdEntityIDs
    }


    struct LineEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .lineStart(entityID) : .lineEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .lineEnd(entityID) : .lineStart(entityID)
        }
    }

    struct ArcEndpoint {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .arcStart(entityID) : .arcEnd(entityID)
        }

        var oppositeReference: SketchReference {
            isStart ? .arcEnd(entityID) : .arcStart(entityID)
        }
    }

    enum SketchCurveEndpoint {
        case line(LineEndpoint)
        case arc(ArcEndpoint)

        var entityID: SketchEntityID {
            switch self {
            case .line(let endpoint):
                endpoint.entityID
            case .arc(let endpoint):
                endpoint.entityID
            }
        }

        var isStart: Bool {
            switch self {
            case .line(let endpoint):
                endpoint.isStart
            case .arc(let endpoint):
                endpoint.isStart
            }
        }

        var reference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.reference
            case .arc(let endpoint):
                endpoint.reference
            }
        }

        var oppositeReference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.oppositeReference
            case .arc(let endpoint):
                endpoint.oppositeReference
            }
        }
    }

    private enum ExtendCurveEndpoint {
        case line(LineEndpoint)
        case arc(ArcEndpoint)
        case spline(entityID: SketchEntityID, isStart: Bool, controlPointIndex: Int)

        var entityID: SketchEntityID {
            switch self {
            case .line(let endpoint):
                endpoint.entityID
            case .arc(let endpoint):
                endpoint.entityID
            case .spline(let entityID, _, _):
                entityID
            }
        }

        var isStart: Bool {
            switch self {
            case .line(let endpoint):
                endpoint.isStart
            case .arc(let endpoint):
                endpoint.isStart
            case .spline(_, let isStart, _):
                isStart
            }
        }

        var reference: SketchReference {
            switch self {
            case .line(let endpoint):
                endpoint.reference
            case .arc(let endpoint):
                endpoint.reference
            case .spline(let entityID, _, let controlPointIndex):
                .splineControlPoint(entity: entityID, index: controlPointIndex)
            }
        }
    }

    private func lineEndpoint(for reference: SketchReference) -> LineEndpoint? {
        switch reference {
        case .lineStart(let entityID):
            LineEndpoint(entityID: entityID, isStart: true)
        case .lineEnd(let entityID):
            LineEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    private func arcEndpoint(for reference: SketchReference) -> ArcEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            ArcEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            ArcEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            nil
        }
    }

    func sketchCurveEndpoint(for reference: SketchReference) -> SketchCurveEndpoint? {
        if let lineEndpoint = lineEndpoint(for: reference) {
            return .line(lineEndpoint)
        }
        if let arcEndpoint = arcEndpoint(for: reference) {
            return .arc(arcEndpoint)
        }
        return nil
    }

    private func extendCurveEndpoint(
        for target: SelectionTarget,
        selection: EditableSketchEntitySelection,
        operationName: String
    ) throws -> ExtendCurveEndpoint {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch entity endpoint target."
            )
        }
        if let reference = componentID.sketchPointHandleReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) endpoint target does not match the selected source curve."
                )
            }
            switch reference.handle {
            case .lineStart:
                return .line(LineEndpoint(entityID: reference.entityID, isStart: true))
            case .lineEnd:
                return .line(LineEndpoint(entityID: reference.entityID, isStart: false))
            case .arcStart:
                return .arc(ArcEndpoint(entityID: reference.entityID, isStart: true))
            case .arcEnd:
                return .arc(ArcEndpoint(entityID: reference.entityID, isStart: false))
            case .point,
                 .circleCenter,
                 .arcCenter:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) requires a line endpoint, arc endpoint, or spline endpoint target."
                )
            }
        }
        if let reference = componentID.sketchControlPointReference {
            guard reference.featureID == selection.featureID,
                  reference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(operationName) control point target does not match the selected source curve."
                )
            }
            guard case .spline(let spline) = selection.entity else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) control point targets are only valid for spline curves."
                )
            }
            if reference.index == 0 {
                return .spline(entityID: reference.entityID, isStart: true, controlPointIndex: 0)
            }
            if reference.index == spline.controlPoints.count - 1 {
                return .spline(
                    entityID: reference.entityID,
                    isStart: false,
                    controlPointIndex: reference.index
                )
            }
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a spline endpoint control point target."
            )
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) follows Plasticity Extend Curve endpoint selection; select a curve endpoint, not the whole curve."
        )
    }

    func adjacentSketchCurveEndpoint(
        to reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (reference: SketchReference, endpoint: SketchCurveEndpoint, entity: SketchEntity) {
        let matches = sketch.constraints.compactMap { constraint -> SketchReference? in
            guard case .coincident(let first, let second) = constraint else {
                return nil
            }
            if first == reference {
                return second
            }
            if second == reference {
                return first
            }
            return nil
        }
        let curveEndpointMatches = matches.compactMap { candidate -> (SketchReference, SketchCurveEndpoint, SketchEntity)? in
            guard let endpoint = sketchCurveEndpoint(for: candidate),
                  let entity = sketch.entities[endpoint.entityID],
                  isSupportedOffsetVertexCurveEntity(entity, endpoint: endpoint) else {
                return nil
            }
            return (candidate, endpoint, entity)
        }
        guard curveEndpointMatches.count == 1,
              let match = curveEndpointMatches.first else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires exactly one adjacent line or arc endpoint at the selected vertex."
            )
        }
        return match
    }

    func refreshedSketchDimension(
        _ dimension: SketchDimension,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchDimension {
        switch dimension {
        case .distance(let from, let to, _):
            let distance = try measuredSketchDistanceDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .distance(from: from, to: to, value: .length(distance, .meter))
        case .angle(let from, let to, _):
            let angle = try measuredSketchAngleDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .angle(from: from, to: to, value: .angle(angle, .radian))
        case .radius(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .radius(entity: entityID, value: .length(radius, .meter))
        case .diameter(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .diameter(entity: entityID, value: .length(radius * 2.0, .meter))
        }
    }

    private func measuredSketchDistanceDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed distance references."
            )
        }
        return hypot(second.x - first.x, second.y - first.y)
    }

    private func measuredSketchAngleDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        if let arcSpan = try measuredSketchArcSpanAngle(
            from: from,
            to: to,
            in: sketch,
            owner: owner
        ) {
            return arcSpan
        }
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed angle references."
            )
        }
        return atan2(second.y - first.y, second.x - first.x)
    }

    func measuredSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        let entityID: SketchEntityID
        switch (from, to) {
        case (.arcStart(let firstID), .arcEnd(let secondID)) where firstID == secondID:
            entityID = firstID
        case (.arcEnd(let firstID), .arcStart(let secondID)) where firstID == secondID:
            entityID = firstID
        default:
            return try measuredConnectedSketchArcSpanAngle(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
        }
        guard let entity = sketch.entities[entityID],
              case .arc(let arc) = entity else {
            return nil
        }
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
    }

    private struct SketchArcPathEndpoint: Hashable {
        var entityID: SketchEntityID
        var isStart: Bool

        var reference: SketchReference {
            isStart ? .arcStart(entityID) : .arcEnd(entityID)
        }
    }

    private struct SketchArcPathGeometry {
        var entityID: SketchEntityID
        var center: (x: Double, y: Double)
        var radius: Double
        var startAngle: Double
        var endAngle: Double
        var span: Double

        var startEndpoint: SketchArcPathEndpoint {
            SketchArcPathEndpoint(entityID: entityID, isStart: true)
        }

        var endEndpoint: SketchArcPathEndpoint {
            SketchArcPathEndpoint(entityID: entityID, isStart: false)
        }
    }

    private func measuredConnectedSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        guard let fromEndpoint = sketchArcPathEndpoint(for: from),
              let toEndpoint = sketchArcPathEndpoint(for: to),
              let seedEntity = sketch.entities[fromEndpoint.entityID],
              case .arc(let seedArc) = seedEntity else {
            return nil
        }
        let seedGeometry = try sketchArcPathGeometry(
            entityID: fromEndpoint.entityID,
            arc: seedArc,
            owner: owner
        )
        var geometries: [SketchEntityID: SketchArcPathGeometry] = [:]
        for (entityID, entity) in sketch.entities {
            guard case .arc(let arc) = entity else {
                continue
            }
            let geometry = try sketchArcPathGeometry(
                entityID: entityID,
                arc: arc,
                owner: owner
            )
            guard sketchArcPathGeometry(geometry, matchesCircleOf: seedGeometry) else {
                continue
            }
            geometries[entityID] = geometry
        }
        guard geometries[toEndpoint.entityID] != nil else {
            return nil
        }
        let spans = [
            connectedSketchArcSpanAngle(
                from: fromEndpoint,
                to: toEndpoint,
                geometries: geometries
            ),
            connectedSketchArcSpanAngle(
                from: toEndpoint,
                to: fromEndpoint,
                geometries: geometries
            ),
        ]
            .compactMap { $0 }
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func sketchArcPathEndpoint(for reference: SketchReference) -> SketchArcPathEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func sketchArcPathGeometry(
        entityID: SketchEntityID,
        arc: SketchArc,
        owner: String
    ) throws -> SketchArcPathGeometry {
        let center = try resolvedPoint(arc.center, owner: "\(owner) arc center")
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return SketchArcPathGeometry(
            entityID: entityID,
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            span: try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        )
    }

    private func sketchArcPathGeometry(
        _ geometry: SketchArcPathGeometry,
        matchesCircleOf seed: SketchArcPathGeometry
    ) -> Bool {
        nearlyEqual(geometry.center.x, seed.center.x, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.center.y, seed.center.y, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.radius, seed.radius, tolerance: 1.0e-9)
    }

    private func connectedSketchArcSpanAngle(
        from start: SketchArcPathEndpoint,
        to target: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> Double? {
        func search(
            from current: SketchArcPathEndpoint,
            accumulatedSpan: Double,
            visitedArcs: Set<SketchEntityID>,
            visitedEndpoints: Set<SketchArcPathEndpoint>
        ) -> [Double] {
            if current == target {
                return [accumulatedSpan]
            }
            guard visitedEndpoints.contains(current) == false else {
                return []
            }
            let nextVisitedEndpoints = visitedEndpoints.union([current])
            var spans: [Double] = []
            if current.isStart,
               visitedArcs.contains(current.entityID) == false,
               let geometry = geometries[current.entityID] {
                spans.append(
                    contentsOf: search(
                        from: geometry.endEndpoint,
                        accumulatedSpan: accumulatedSpan + geometry.span,
                        visitedArcs: visitedArcs.union([current.entityID]),
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            for endpoint in matchingSketchArcPathEndpoints(
                current,
                geometries: geometries
            ) where endpoint != current {
                spans.append(
                    contentsOf: search(
                        from: endpoint,
                        accumulatedSpan: accumulatedSpan,
                        visitedArcs: visitedArcs,
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            return spans
        }
        let spans = search(
            from: start,
            accumulatedSpan: 0.0,
            visitedArcs: [],
            visitedEndpoints: []
        )
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func matchingSketchArcPathEndpoints(
        _ endpoint: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> [SketchArcPathEndpoint] {
        guard let source = geometries[endpoint.entityID] else {
            return []
        }
        let sourcePoint = sketchArcPathPoint(endpoint, geometry: source)
        return geometries.values.flatMap { geometry in
            [geometry.startEndpoint, geometry.endEndpoint].filter { candidate in
                let point = sketchArcPathPoint(candidate, geometry: geometry)
                return nearlyEqual(point.x, sourcePoint.x, tolerance: 1.0e-9) &&
                    nearlyEqual(point.y, sourcePoint.y, tolerance: 1.0e-9)
            }
        }
    }

    private func sketchArcPathPoint(
        _ endpoint: SketchArcPathEndpoint,
        geometry: SketchArcPathGeometry
    ) -> (x: Double, y: Double) {
        let angle = endpoint.isStart ? geometry.startAngle : geometry.endAngle
        return (
            x: geometry.center.x + cos(angle) * geometry.radius,
            y: geometry.center.y + sin(angle) * geometry.radius
        )
    }

    private func uniqueSketchArcPathSpans(_ spans: [Double]) -> [Double] {
        spans.reduce(into: []) { uniqueSpans, span in
            guard uniqueSpans.contains(where: { nearlyEqual($0, span, tolerance: 1.0e-9) }) == false else {
                return
            }
            uniqueSpans.append(span)
        }
    }

    private func measuredSketchCircularRadius(
        _ entityID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing circular entity."
            )
        }
        switch entity {
        case .circle(let circle):
            return try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
        case .arc(let arc):
            return try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        case .point,
             .line,
             .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a circle or arc dimension target."
            )
        }
    }

    private func normalizedNonnegativeAngleSpan(
        from startAngle: Double,
        to endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span < 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    func isSupportedOffsetVertexCurveEntity(
        _ entity: SketchEntity,
        endpoint: SketchCurveEndpoint
    ) -> Bool {
        switch (entity, endpoint) {
        case (.line, .line),
             (.arc, .arc):
            return true
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            return false
        }
    }

    private func validateSketchCurveCanExtend(
        selection: EditableSketchEntitySelection,
        endpoint: ExtendCurveEndpoint,
        shape: ExtendCurveShape
    ) throws {
        guard selection.entityID == endpoint.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Sketch curve extend endpoint target does not match the selected curve."
            )
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot edit a generated Bridge Curve source."
            )
        }

        switch (selection.entity, endpoint) {
        case (.line, .line):
            guard shape != .arc else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend Arc shape for line curves requires arc construction parameters."
                )
            }
        case (.arc, .arc):
            guard shape != .linear else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend Linear shape for arcs would create a new tangent line segment and is not supported yet."
                )
            }
        case (.spline(let spline), .spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend requires an open spline curve."
                )
            }
            guard shape == .linear else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve extend supports spline extension with Linear shape only until higher-continuity spline extension is implemented."
                )
            }
        case (.point, _),
             (.circle, _),
             (.line, _),
             (.arc, _),
             (.spline, _):
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend requires an endpoint target that belongs to the selected source curve type."
            )
        }

        for constraint in selection.sketch.constraints where sketchCurveExtendBlocksConstraint(
            constraint,
            entityID: selection.entityID,
            endpoint: endpoint,
            entity: selection.entity
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot preserve an attached constraint on the moved endpoint or whole curve yet."
            )
        }
        for dimension in selection.sketch.dimensions where sketchCurveExtendBlocksDimension(
            dimension,
            entityID: selection.entityID,
            entity: selection.entity
        ) {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve extend cannot preserve dimensions attached to the changing curve extent yet."
            )
        }
    }

    private func extendedSketchCurveEntity(
        _ entity: SketchEntity,
        endpoint: ExtendCurveEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchEntity {
        switch (entity, endpoint) {
        case (.line(let line), .line(let lineEndpoint)):
            let extended = try extendedLine(
                line,
                endpoint: lineEndpoint,
                distance: distance,
                shape: shape,
                owner: owner
            )
            return .line(extended)
        case (.arc(let arc), .arc(let arcEndpoint)):
            let extended = try extendedArc(
                arc,
                endpoint: arcEndpoint,
                distance: distance,
                resolvedDistance: resolvedDistance,
                shape: shape,
                owner: owner
            )
            return .arc(extended)
        case (.spline(let spline), .spline):
            let extended = try extendedSpline(
                spline,
                endpoint: endpoint,
                distance: distance,
                shape: shape,
                owner: owner
            )
            return .spline(extended)
        case (.point, _),
             (.circle, _),
             (.line, _),
             (.arc, _),
             (.spline, _):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint target does not match the selected curve type."
            )
        }
    }

    private func extendedLine(
        _ line: SketchLine,
        endpoint: LineEndpoint,
        distance: CADExpression,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchLine {
        guard shape != .arc else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Arc shape for line curves requires arc construction parameters."
            )
        }
        let metrics = try resolvedLineMetrics(line, owner: owner)
        let directionX = cos(metrics.angleRadians) * (endpoint.isStart ? -1.0 : 1.0)
        let directionY = sin(metrics.angleRadians) * (endpoint.isStart ? -1.0 : 1.0)
        let extendedPoint = translatedSketchPoint(
            endpoint.isStart ? line.start : line.end,
            directionX: directionX,
            directionY: directionY,
            distance: distance
        )
        let extended = endpoint.isStart
            ? SketchLine(start: extendedPoint, end: line.end)
            : SketchLine(start: line.start, end: extendedPoint)
        _ = try resolvedLineMetrics(extended, owner: owner)
        return extended
    }

    private func extendedArc(
        _ arc: SketchArc,
        endpoint: ArcEndpoint,
        distance: CADExpression,
        resolvedDistance: Double,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchArc {
        guard shape != .linear else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Linear shape for arcs would create a new tangent line segment and is not supported yet."
            )
        }
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let deltaAngle = resolvedDistance / radius
        guard span + deltaAngle < (2.0 * Double.pi) - 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot extend an arc to a full or over-full circle."
            )
        }
        let deltaAngleExpression = CADExpression.multiply(
            .angle(1.0, .radian),
            .divide(distance, arc.radius)
        )
        let extended = endpoint.isStart
            ? SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: .subtract(arc.startAngle, deltaAngleExpression),
                endAngle: arc.endAngle
            )
            : SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: .add(arc.endAngle, deltaAngleExpression)
            )
        try validateArc(extended, owner: owner)
        return extended
    }

    private func extendedSpline(
        _ spline: SketchSpline,
        endpoint: ExtendCurveEndpoint,
        distance: CADExpression,
        shape: ExtendCurveShape,
        owner: String
    ) throws -> SketchSpline {
        guard case .spline(_, let isStart, _) = endpoint else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a spline endpoint target."
            )
        }
        guard shape == .linear else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) supports spline extension with Linear shape only."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an open spline curve."
            )
        }
        try validateSpline(spline, owner: owner)

        var updated = spline
        if isStart {
            let first = spline.controlPoints[0]
            let next = spline.controlPoints[1]
            let direction = try normalizedDirection(
                from: next,
                to: first,
                owner: "\(owner) start tangent"
            )
            updated.controlPoints = [
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance),
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance, scale: 2.0 / 3.0),
                translatedSketchPoint(first, directionX: direction.x, directionY: direction.y, distance: distance, scale: 1.0 / 3.0),
            ] + spline.controlPoints
        } else {
            let count = spline.controlPoints.count
            let previous = spline.controlPoints[count - 2]
            let last = spline.controlPoints[count - 1]
            let direction = try normalizedDirection(
                from: previous,
                to: last,
                owner: "\(owner) end tangent"
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance, scale: 1.0 / 3.0)
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance, scale: 2.0 / 3.0)
            )
            updated.controlPoints.append(
                translatedSketchPoint(last, directionX: direction.x, directionY: direction.y, distance: distance)
            )
        }
        try validateSpline(updated, owner: owner)
        return updated
    }

    func translatedSketchPoint(
        _ point: SketchPoint,
        directionX: Double,
        directionY: Double,
        distance: CADExpression,
        scale: Double = 1.0
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(distance, .scalar(directionX * scale))),
            y: .add(point.y, .multiply(distance, .scalar(directionY * scale)))
        )
    }

    func normalizedDirection(
        from start: SketchPoint,
        to end: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let startX = try resolvedLengthValue(start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) direction must not collapse to zero."
            )
        }
        return (x: deltaX / length, y: deltaY / length)
    }

    private func sketchCurveExtendBlocksConstraint(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        endpoint: ExtendCurveEndpoint,
        entity: SketchEntity
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return first == endpoint.reference || second == endpoint.reference
        case .fixed(let reference):
            return reference == endpoint.reference || reference == .entity(entityID)
        case .horizontal(let id),
             .vertical(let id):
            if case .line = entity {
                return false
            }
            return id == entityID
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if case .arc = entity {
                return false
            }
            return first == entityID || second == entityID
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second):
            return first == entityID || second == entityID
        case .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .splineEndpointTangent(let splineID, _, let lineID):
            return splineID == entityID || lineID == entityID
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return first.splineID == entityID || second.splineID == entityID
        }
    }

    private func sketchCurveExtendBlocksDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) -> Bool {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            return sketchReference(from, references: entityID) ||
                sketchReference(to, references: entityID)
        case .radius(let id, _),
             .diameter(let id, _):
            if case .arc = entity {
                return false
            }
            return id == entityID
        }
    }

    func dimensionReferencesAny(
        _ dimension: SketchDimension,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch dimension {
        case .distance(let first, let second, _),
             .angle(let first, let second, _):
            entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .radius(let entityID, _),
             .diameter(let entityID, _):
            entityIDs.contains(entityID)
        }
    }

    func constraintReferencesAny(
        _ constraint: SketchConstraint,
        entityIDs: Set<SketchEntityID>
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return entityIDs.contains(entityID(for: first)) || entityIDs.contains(entityID(for: second))
        case .horizontal(let entityID),
             .vertical(let entityID),
             .smoothSplineControlPoint(let entityID, _):
            return entityIDs.contains(entityID)
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return entityIDs.contains(first) || entityIDs.contains(second)
        case .splineEndpointTangent(let splineID, _, let lineID):
            return entityIDs.contains(splineID) || entityIDs.contains(lineID)
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return entityIDs.contains(first.splineID) || entityIDs.contains(second.splineID)
        case .fixed(let reference):
            return entityIDs.contains(entityID(for: reference))
        }
    }

    func entityID(for reference: SketchReference) -> SketchEntityID {
        switch reference {
        case .entity(let entityID),
             .lineStart(let entityID),
             .lineEnd(let entityID),
             .circleCenter(let entityID),
             .circleRadius(let entityID),
             .arcCenter(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID),
             .arcRadius(let entityID),
             .splineControlPoint(let entityID, _):
            entityID
        }
    }

    func resolvedLineMetrics(
        _ line: SketchLine,
        owner: String
    ) throws -> (length: Double, angleRadians: Double, angleDegrees: Double) {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) length must be greater than zero."
            )
        }
        let angleRadians = atan2(deltaY, deltaX)
        return (
            length: length,
            angleRadians: angleRadians,
            angleDegrees: angleRadians * 180.0 / .pi
        )
    }

    func resizedLine(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + deltaX / currentLength * length,
                y: startY + deltaY / currentLength * length
            )
        )
    }

    func resizedLinePreservingEnd(
        _ line: SketchLine,
        length: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        let currentLength = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard currentLength > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return SketchLine(
            start: sketchPoint(
                x: endX - deltaX / currentLength * length,
                y: endY - deltaY / currentLength * length
            ),
            end: line.end
        )
    }

    func angledLinePreservingStart(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: line.start,
            end: sketchPoint(
                x: startX + cos(angleRadians) * length,
                y: startY + sin(angleRadians) * length
            )
        )
    }

    func angledLinePreservingEnd(
        _ line: SketchLine,
        angleRadians: Double,
        owner: String
    ) throws -> SketchLine {
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let length = try resolvedLineMetrics(line, owner: owner).length
        return SketchLine(
            start: sketchPoint(
                x: endX - cos(angleRadians) * length,
                y: endY - sin(angleRadians) * length
            ),
            end: line.end
        )
    }

    func angularDistance(_ first: Double, _ second: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = (first - second).truncatingRemainder(dividingBy: fullCircle)
        if delta > Double.pi {
            delta -= fullCircle
        }
        if delta < -Double.pi {
            delta += fullCircle
        }
        return abs(delta)
    }

    private func lineOrientationDistance(_ first: Double, _ second: Double) -> Double {
        let period = Double.pi
        var delta = (first - second).truncatingRemainder(dividingBy: period)
        if delta > period / 2.0 {
            delta -= period
        }
        if delta < -period / 2.0 {
            delta += period
        }
        return abs(delta)
    }

    func validateLineAngleDimensionAgainstDirectOrientationConstraints(
        _ angleRadians: Double,
        lineID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        for constraint in sketch.constraints {
            switch constraint {
            case .horizontal(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, 0.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a horizontal sketch constraint."
                    )
                }
            case .vertical(let constrainedLineID) where constrainedLineID == lineID:
                guard lineOrientationDistance(angleRadians, Double.pi / 2.0) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "\(owner) conflicts with a vertical sketch constraint."
                    )
                }
            default:
                continue
            }
        }
    }

    func positiveArcSpan(
        startAngle: Double,
        endAngle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= 0.0 {
            span += fullCircle
        }
        while span > fullCircle {
            span -= fullCircle
        }
        return span
    }

    private struct RebuiltSketchSpline {
        var spline: SketchSpline
        var originalControlPointCount: Int
        var rebuiltControlPointCount: Int
        var originalSegmentCount: Int
        var rebuiltSegmentCount: Int
        var deviation: SketchSplineRebuildDeviation
        var controlPointIndexMap: [Int: Int]

        var changesControlPointCount: Bool {
            originalControlPointCount != rebuiltControlPointCount
        }
    }

    private struct SketchSplineRebuildDeviation {
        var maximumDistance: Double
        var rootMeanSquareDistance: Double
        var maximumDistanceFraction: Double
        var evaluatedIntervalCount: Int
        var criticalPointCount: Int
    }

    private struct SketchSplineRebuildSample {
        var point: CADCore.Point2D
        var derivative: CADCore.Point2D
    }

    private enum SketchSplineRebuildSampleSide {
        case before
        case after
    }

    private struct SketchSplineRebuildInterval {
        var startFraction: Double
        var endFraction: Double
        var segmentCount: Int
    }

    private struct CubicBezierSegment2D {
        var p0: CADCore.Point2D
        var p1: CADCore.Point2D
        var p2: CADCore.Point2D
        var p3: CADCore.Point2D
    }

    private struct CubicSplineSegmentLocation {
        var segmentIndex: Int
        var localFraction: Double
    }

    private struct AnalyticCubicBezierDeviation {
        var maximumSquaredDistance: Double
        var maximumDistanceFraction: Double
        var squaredDistanceIntegral: Double
        var criticalPointCount: Int
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

    private func rebuiltSketchSplineByPointCount(
        _ spline: SketchSpline,
        controlPointCount: Int,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard controlPointCount >= 4,
              (controlPointCount - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Points method requires a 3n + 1 control point count of at least 4."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let rebuiltSegmentCount = (controlPointCount - 1) / 3
        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: rebuiltSegmentCount
                ),
            ],
            tangentWeight: 1.0,
            owner: owner
        )
    }

    private func rebuiltSketchSplineByRefit(
        _ spline: SketchSpline,
        tolerance: CADExpression,
        keepsCorners: Bool,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let toleranceMeters = try resolvedPositiveLengthValue(
            tolerance,
            owner: "\(owner) Refit tolerance"
        )
        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let intervals: [SketchSplineRebuildInterval]
        if keepsCorners {
            intervals = try refitIntervalsKeepingCorners(
                originalControlPoints,
                originalSegmentCount: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
        } else {
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: 0.0,
                endFraction: 1.0,
                originalSegmentSpan: originalSegmentCount,
                tolerance: toleranceMeters,
                owner: owner
            )
            intervals = [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: segmentCount
                ),
            ]
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: intervals,
            tangentWeight: 1.0,
            owner: owner
        )
    }

    private func rebuiltSketchSplineByExplicitControl(
        _ spline: SketchSpline,
        degree: Int,
        spanCount: Int,
        weight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        guard degree == 3 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control currently supports degree 3 cubic Bezier output; degree \(degree) requires a B-spline/NURBS source model."
            )
        }
        guard spanCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control requires at least one span."
            )
        }
        guard weight.isFinite,
              weight >= 0.0,
              weight <= 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) Explicit Control weight must be between 0 and 1."
            )
        }

        let originalControlPoints = try resolvedSplineControlPoints(
            spline,
            owner: owner
        )
        guard originalControlPoints.count >= 4,
              (originalControlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }

        return try rebuiltSketchSpline(
            from: spline,
            originalControlPoints: originalControlPoints,
            intervals: [
                SketchSplineRebuildInterval(
                    startFraction: 0.0,
                    endFraction: 1.0,
                    segmentCount: spanCount
                ),
            ],
            tangentWeight: weight,
            owner: owner
        )
    }

    private func rebuiltSketchSpline(
        from spline: SketchSpline,
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        tangentWeight: Double,
        owner: String
    ) throws -> RebuiltSketchSpline {
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = intervals.reduce(0) { $0 + $1.segmentCount }
        guard rebuiltSegmentCount > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires at least one rebuilt span."
            )
        }
        var rebuiltControlPoints: [SketchPoint] = []
        rebuiltControlPoints.reserveCapacity(rebuiltSegmentCount * 3 + 1)
        var indexMap: [Int: Int] = [:]

        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }

            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let handles = sketchSplineRebuildHandles(
                    start: start,
                    end: end,
                    span: span,
                    tangentWeight: tangentWeight
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(
                        sketchPoint(x: start.point.x, y: start.point.y)
                    )
                    mapOriginalKnotIfAligned(
                        fraction: startFraction,
                        originalSegmentCount: originalSegmentCount,
                        rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                        into: &indexMap
                    )
                }
                rebuiltControlPoints.append(sketchPoint(x: handles.first.x, y: handles.first.y))
                rebuiltControlPoints.append(sketchPoint(x: handles.second.x, y: handles.second.y))
                rebuiltControlPoints.append(sketchPoint(x: end.point.x, y: end.point.y))
                mapOriginalKnotIfAligned(
                    fraction: endFraction,
                    originalSegmentCount: originalSegmentCount,
                    rebuiltControlPointIndex: rebuiltControlPoints.count - 1,
                    into: &indexMap
                )
            }
        }

        let rebuiltSpline = SketchSpline(
            controlPoints: rebuiltControlPoints,
            isClosed: spline.isClosed
        )
        try validateSpline(rebuiltSpline, owner: owner)
        let rebuiltControlPointValues = try resolvedSplineControlPoints(
            rebuiltSpline,
            owner: owner
        )
        let deviation = try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPointValues,
            startFraction: 0.0,
            endFraction: 1.0
        )
        return RebuiltSketchSpline(
            spline: rebuiltSpline,
            originalControlPointCount: originalControlPoints.count,
            rebuiltControlPointCount: rebuiltControlPoints.count,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount,
            deviation: deviation,
            controlPointIndexMap: indexMap
        )
    }

    private func sketchSplineRebuildHandles(
        start: SketchSplineRebuildSample,
        end: SketchSplineRebuildSample,
        span: Double,
        tangentWeight: Double
    ) -> (first: CADCore.Point2D, second: CADCore.Point2D) {
        let chord = CADCore.Point2D(
            x: end.point.x - start.point.x,
            y: end.point.y - start.point.y
        )
        let chordFirst = CADCore.Point2D(
            x: start.point.x + chord.x / 3.0,
            y: start.point.y + chord.y / 3.0
        )
        let chordSecond = CADCore.Point2D(
            x: end.point.x - chord.x / 3.0,
            y: end.point.y - chord.y / 3.0
        )
        let tangentFirst = CADCore.Point2D(
            x: start.point.x + start.derivative.x * span / 3.0,
            y: start.point.y + start.derivative.y * span / 3.0
        )
        let tangentSecond = CADCore.Point2D(
            x: end.point.x - end.derivative.x * span / 3.0,
            y: end.point.y - end.derivative.y * span / 3.0
        )
        return (
            first: interpolate(
                from: chordFirst,
                to: tangentFirst,
                fraction: tangentWeight
            ),
            second: interpolate(
                from: chordSecond,
                to: tangentSecond,
                fraction: tangentWeight
            )
        )
    }

    private func interpolate(
        from first: CADCore.Point2D,
        to second: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        CADCore.Point2D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction
        )
    }

    private func refitIntervalsKeepingCorners(
        _ originalControlPoints: [CADCore.Point2D],
        originalSegmentCount: Int,
        tolerance: Double,
        owner: String
    ) throws -> [SketchSplineRebuildInterval] {
        let cornerBoundaries = cornerKnotSegmentBoundaries(
            originalControlPoints
        )
        var boundaries = [0]
        boundaries.append(contentsOf: cornerBoundaries)
        boundaries.append(originalSegmentCount)

        var intervals: [SketchSplineRebuildInterval] = []
        intervals.reserveCapacity(boundaries.count - 1)
        for index in 0 ..< boundaries.count - 1 {
            let startBoundary = boundaries[index]
            let endBoundary = boundaries[index + 1]
            let span = endBoundary - startBoundary
            guard span > 0 else {
                continue
            }
            let startFraction = Double(startBoundary) / Double(originalSegmentCount)
            let endFraction = Double(endBoundary) / Double(originalSegmentCount)
            let segmentCount = try refitSegmentCount(
                originalControlPoints: originalControlPoints,
                startFraction: startFraction,
                endFraction: endFraction,
                originalSegmentSpan: span,
                tolerance: tolerance,
                owner: owner
            )
            intervals.append(
                SketchSplineRebuildInterval(
                    startFraction: startFraction,
                    endFraction: endFraction,
                    segmentCount: segmentCount
                )
            )
        }
        return intervals
    }

    private func refitSegmentCount(
        originalControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double,
        originalSegmentSpan: Int,
        tolerance: Double,
        owner: String
    ) throws -> Int {
        for segmentCount in 1 ... originalSegmentSpan {
            let candidateControlPoints = try rebuiltSketchSplineControlPoints(
                originalControlPoints: originalControlPoints,
                intervals: [
                    SketchSplineRebuildInterval(
                        startFraction: startFraction,
                        endFraction: endFraction,
                        segmentCount: segmentCount
                    ),
                ],
                owner: owner
            )
            let deviation = try maxSketchSplineDeviation(
                originalControlPoints: originalControlPoints,
                rebuiltControlPoints: candidateControlPoints,
                startFraction: startFraction,
                endFraction: endFraction
            )
            if deviation <= tolerance {
                return segmentCount
            }
        }
        return originalSegmentSpan
    }

    private func rebuiltSketchSplineControlPoints(
        originalControlPoints: [CADCore.Point2D],
        intervals: [SketchSplineRebuildInterval],
        owner: String
    ) throws -> [CADCore.Point2D] {
        var rebuiltControlPoints: [CADCore.Point2D] = []
        for interval in intervals {
            guard interval.segmentCount > 0,
                  interval.endFraction > interval.startFraction else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) generated an invalid rebuild interval."
                )
            }
            for segmentIndex in 0 ..< interval.segmentCount {
                let localStart = Double(segmentIndex) / Double(interval.segmentCount)
                let localEnd = Double(segmentIndex + 1) / Double(interval.segmentCount)
                let startFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localStart
                let endFraction = interval.startFraction
                    + (interval.endFraction - interval.startFraction) * localEnd
                let start = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: startFraction,
                    side: .after
                )
                let end = try sketchSplineRebuildSample(
                    on: originalControlPoints,
                    fraction: endFraction,
                    side: .before
                )
                let span = endFraction - startFraction
                let firstHandle = CADCore.Point2D(
                    x: start.point.x + start.derivative.x * span / 3.0,
                    y: start.point.y + start.derivative.y * span / 3.0
                )
                let secondHandle = CADCore.Point2D(
                    x: end.point.x - end.derivative.x * span / 3.0,
                    y: end.point.y - end.derivative.y * span / 3.0
                )

                if rebuiltControlPoints.isEmpty {
                    rebuiltControlPoints.append(start.point)
                }
                rebuiltControlPoints.append(firstHandle)
                rebuiltControlPoints.append(secondHandle)
                rebuiltControlPoints.append(end.point)
            }
        }
        return rebuiltControlPoints
    }

    private func maxSketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> Double {
        try sketchSplineDeviation(
            originalControlPoints: originalControlPoints,
            rebuiltControlPoints: rebuiltControlPoints,
            startFraction: startFraction,
            endFraction: endFraction
        ).maximumDistance
    }

    private func sketchSplineDeviation(
        originalControlPoints: [CADCore.Point2D],
        rebuiltControlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> SketchSplineRebuildDeviation {
        guard endFraction > startFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild generated an invalid deviation range."
            )
        }
        let originalSegmentCount = (originalControlPoints.count - 1) / 3
        let rebuiltSegmentCount = (rebuiltControlPoints.count - 1) / 3
        let boundaries = sketchSplineDeviationBoundaries(
            startFraction: startFraction,
            endFraction: endFraction,
            originalSegmentCount: originalSegmentCount,
            rebuiltSegmentCount: rebuiltSegmentCount
        )

        var maximumSquaredDistance = 0.0
        var maximumDistanceFraction = startFraction
        var squaredDistanceIntegral = 0.0
        var criticalPointCount = 0
        var evaluatedIntervalCount = 0

        for index in 0 ..< boundaries.count - 1 {
            let intervalStart = boundaries[index]
            let intervalEnd = boundaries[index + 1]
            guard intervalEnd > intervalStart + 1.0e-14 else {
                continue
            }
            let originalSegment = try cubicBezierSubcurve(
                controlPoints: originalControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let rebuiltSegment = try cubicBezierSubcurve(
                controlPoints: rebuiltControlPoints,
                startFraction: intervalStart,
                endFraction: intervalEnd
            )
            let intervalDeviation = analyticCubicBezierDeviation(
                original: originalSegment,
                rebuilt: rebuiltSegment,
                globalStartFraction: intervalStart,
                globalEndFraction: intervalEnd
            )
            evaluatedIntervalCount += 1
            criticalPointCount += intervalDeviation.criticalPointCount
            squaredDistanceIntegral += intervalDeviation.squaredDistanceIntegral
            if intervalDeviation.maximumSquaredDistance > maximumSquaredDistance {
                maximumSquaredDistance = intervalDeviation.maximumSquaredDistance
                maximumDistanceFraction = intervalDeviation.maximumDistanceFraction
            }
        }
        let rangeLength = endFraction - startFraction
        let meanSquaredDistance = squaredDistanceIntegral / rangeLength
        return SketchSplineRebuildDeviation(
            maximumDistance: sqrt(max(0.0, maximumSquaredDistance)),
            rootMeanSquareDistance: sqrt(max(0.0, meanSquaredDistance)),
            maximumDistanceFraction: maximumDistanceFraction,
            evaluatedIntervalCount: evaluatedIntervalCount,
            criticalPointCount: criticalPointCount
        )
    }

    private func sketchSplineDeviationBoundaries(
        startFraction: Double,
        endFraction: Double,
        originalSegmentCount: Int,
        rebuiltSegmentCount: Int
    ) -> [Double] {
        var boundaries = [startFraction, endFraction]
        appendSplineSegmentBoundaries(
            segmentCount: originalSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        appendSplineSegmentBoundaries(
            segmentCount: rebuiltSegmentCount,
            startFraction: startFraction,
            endFraction: endFraction,
            to: &boundaries
        )
        return sortedUniqueFractions(boundaries)
    }

    private func appendSplineSegmentBoundaries(
        segmentCount: Int,
        startFraction: Double,
        endFraction: Double,
        to boundaries: inout [Double]
    ) {
        guard segmentCount > 1 else {
            return
        }
        for boundaryIndex in 1 ..< segmentCount {
            let boundary = Double(boundaryIndex) / Double(segmentCount)
            if boundary > startFraction + 1.0e-12,
               boundary < endFraction - 1.0e-12 {
                boundaries.append(boundary)
            }
        }
    }

    private func sortedUniqueFractions(_ fractions: [Double]) -> [Double] {
        var unique: [Double] = []
        for fraction in fractions.sorted() {
            if unique.last.map({ abs($0 - fraction) <= 1.0e-12 }) == true {
                continue
            }
            unique.append(fraction)
        }
        return unique
    }

    private func cubicBezierSubcurve(
        controlPoints: [CADCore.Point2D],
        startFraction: Double,
        endFraction: Double
    ) throws -> CubicBezierSegment2D {
        let start = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: startFraction,
            side: .after
        )
        let end = try cubicSplineSegmentLocation(
            controlPoints: controlPoints,
            fraction: endFraction,
            side: .before
        )
        guard start.segmentIndex == end.segmentIndex,
              end.localFraction > start.localFraction else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild deviation interval must stay inside one cubic span."
            )
        }

        let segmentStart = start.segmentIndex * 3
        var segment = CubicBezierSegment2D(
            p0: controlPoints[segmentStart],
            p1: controlPoints[segmentStart + 1],
            p2: controlPoints[segmentStart + 2],
            p3: controlPoints[segmentStart + 3]
        )
        if start.localFraction > 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: start.localFraction
            ).right
        }
        let remainingLength = 1.0 - start.localFraction
        let endInTrimmedSegment = (end.localFraction - start.localFraction) / remainingLength
        if endInTrimmedSegment < 1.0 - 1.0e-14 {
            segment = splitCubicBezier(
                segment,
                fraction: endInTrimmedSegment
            ).left
        }
        return segment
    }

    private func cubicSplineSegmentLocation(
        controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> CubicSplineSegmentLocation {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild requires a cubic Bezier spline."
            )
        }

        let segmentCount = (controlPoints.count - 1) / 3
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let scaledFraction = clampedFraction * Double(segmentCount)
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            return CubicSplineSegmentLocation(segmentIndex: 0, localFraction: 0.0)
        }
        if scaledFraction >= Double(segmentCount) {
            return CubicSplineSegmentLocation(segmentIndex: segmentCount - 1, localFraction: 1.0)
        }
        if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                return CubicSplineSegmentLocation(
                    segmentIndex: max(0, boundary - 1),
                    localFraction: 1.0
                )
            case .after:
                return CubicSplineSegmentLocation(
                    segmentIndex: min(segmentCount - 1, boundary),
                    localFraction: 0.0
                )
            }
        }
        let segmentIndex = max(0, Int(floor(scaledFraction)))
        return CubicSplineSegmentLocation(
            segmentIndex: segmentIndex,
            localFraction: scaledFraction - Double(segmentIndex)
        )
    }

    private func splitCubicBezier(
        _ segment: CubicBezierSegment2D,
        fraction: Double
    ) -> (left: CubicBezierSegment2D, right: CubicBezierSegment2D) {
        let q0 = interpolate(from: segment.p0, to: segment.p1, fraction: fraction)
        let q1 = interpolate(from: segment.p1, to: segment.p2, fraction: fraction)
        let q2 = interpolate(from: segment.p2, to: segment.p3, fraction: fraction)
        let r0 = interpolate(from: q0, to: q1, fraction: fraction)
        let r1 = interpolate(from: q1, to: q2, fraction: fraction)
        let s = interpolate(from: r0, to: r1, fraction: fraction)
        return (
            left: CubicBezierSegment2D(p0: segment.p0, p1: q0, p2: r0, p3: s),
            right: CubicBezierSegment2D(p0: s, p1: r1, p2: q2, p3: segment.p3)
        )
    }

    private func analyticCubicBezierDeviation(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D,
        globalStartFraction: Double,
        globalEndFraction: Double
    ) -> AnalyticCubicBezierDeviation {
        let squaredDistance = squaredDistancePolynomial(
            original: original,
            rebuilt: rebuilt
        )
        let derivative = polynomialDerivative(squaredDistance)
        let roots = polynomialRootsInUnitInterval(derivative)
            .filter { $0 > 1.0e-10 && $0 < 1.0 - 1.0e-10 }
        let candidates = [0.0, 1.0] + roots
        var maximumSquaredDistance = 0.0
        var maximumLocalFraction = 0.0
        for candidate in candidates {
            let value = max(0.0, polynomialEvaluate(squaredDistance, at: candidate))
            if value > maximumSquaredDistance {
                maximumSquaredDistance = value
                maximumLocalFraction = candidate
            }
        }
        let intervalLength = globalEndFraction - globalStartFraction
        let squaredDistanceIntegral = intervalLength
            * max(0.0, polynomialUnitIntegral(squaredDistance))
        return AnalyticCubicBezierDeviation(
            maximumSquaredDistance: maximumSquaredDistance,
            maximumDistanceFraction: globalStartFraction
                + intervalLength * maximumLocalFraction,
            squaredDistanceIntegral: squaredDistanceIntegral,
            criticalPointCount: roots.count
        )
    }

    private func squaredDistancePolynomial(
        original: CubicBezierSegment2D,
        rebuilt: CubicBezierSegment2D
    ) -> [Double] {
        let originalX = cubicBezierPowerCoefficients(
            original.p0.x,
            original.p1.x,
            original.p2.x,
            original.p3.x
        )
        let originalY = cubicBezierPowerCoefficients(
            original.p0.y,
            original.p1.y,
            original.p2.y,
            original.p3.y
        )
        let rebuiltX = cubicBezierPowerCoefficients(
            rebuilt.p0.x,
            rebuilt.p1.x,
            rebuilt.p2.x,
            rebuilt.p3.x
        )
        let rebuiltY = cubicBezierPowerCoefficients(
            rebuilt.p0.y,
            rebuilt.p1.y,
            rebuilt.p2.y,
            rebuilt.p3.y
        )
        let deltaX = zip(originalX, rebuiltX).map { $0 - $1 }
        let deltaY = zip(originalY, rebuiltY).map { $0 - $1 }
        return polynomialAdd(
            polynomialMultiply(deltaX, deltaX),
            polynomialMultiply(deltaY, deltaY)
        )
    }

    private func cubicBezierPowerCoefficients(
        _ p0: Double,
        _ p1: Double,
        _ p2: Double,
        _ p3: Double
    ) -> [Double] {
        [
            p0,
            -3.0 * p0 + 3.0 * p1,
            3.0 * p0 - 6.0 * p1 + 3.0 * p2,
            -p0 + 3.0 * p1 - 3.0 * p2 + p3,
        ]
    }

    private func polynomialAdd(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        let count = max(lhs.count, rhs.count)
        var result = Array(repeating: 0.0, count: count)
        for index in lhs.indices {
            result[index] += lhs[index]
        }
        for index in rhs.indices {
            result[index] += rhs[index]
        }
        return result
    }

    private func polynomialMultiply(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        guard lhs.isEmpty == false,
              rhs.isEmpty == false else {
            return []
        }
        var result = Array(repeating: 0.0, count: lhs.count + rhs.count - 1)
        for lhsIndex in lhs.indices {
            for rhsIndex in rhs.indices {
                result[lhsIndex + rhsIndex] += lhs[lhsIndex] * rhs[rhsIndex]
            }
        }
        return result
    }

    private func polynomialDerivative(_ coefficients: [Double]) -> [Double] {
        guard coefficients.count > 1 else {
            return [0.0]
        }
        return coefficients.dropFirst().enumerated().map { index, coefficient in
            coefficient * Double(index + 1)
        }
    }

    private func polynomialUnitIntegral(_ coefficients: [Double]) -> Double {
        coefficients.enumerated().reduce(0.0) { partial, element in
            partial + element.element / Double(element.offset + 1)
        }
    }

    private func polynomialEvaluate(
        _ coefficients: [Double],
        at fraction: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) { partial, coefficient in
            partial * fraction + coefficient
        }
    }

    private func polynomialRootsInUnitInterval(_ coefficients: [Double]) -> [Double] {
        let trimmed = trimmedPolynomial(coefficients)
        let degree = trimmed.count - 1
        guard degree > 0 else {
            return []
        }
        let valueTolerance = polynomialValueTolerance(trimmed)
        if degree == 1 {
            let root = -trimmed[0] / trimmed[1]
            guard root >= -1.0e-12,
                  root <= 1.0 + 1.0e-12 else {
                return []
            }
            return [min(max(root, 0.0), 1.0)]
        }

        let criticalPoints = polynomialRootsInUnitInterval(
            polynomialDerivative(trimmed)
        )
        let splitPoints = sortedUniqueFractions([0.0] + criticalPoints + [1.0])
        var roots: [Double] = []
        for point in splitPoints where abs(polynomialEvaluate(trimmed, at: point)) <= valueTolerance {
            roots.append(point)
        }
        for index in 0 ..< splitPoints.count - 1 {
            let start = splitPoints[index]
            let end = splitPoints[index + 1]
            guard end > start + 1.0e-12 else {
                continue
            }
            let startValue = polynomialEvaluate(trimmed, at: start)
            let endValue = polynomialEvaluate(trimmed, at: end)
            if startValue * endValue < 0.0 {
                roots.append(
                    bisectedPolynomialRoot(
                        trimmed,
                        lower: start,
                        upper: end,
                        lowerValue: startValue,
                        tolerance: valueTolerance
                    )
                )
            }
        }
        return sortedUniqueFractions(
            roots.map { min(max($0, 0.0), 1.0) }
        )
    }

    private func bisectedPolynomialRoot(
        _ coefficients: [Double],
        lower: Double,
        upper: Double,
        lowerValue: Double,
        tolerance: Double
    ) -> Double {
        var low = lower
        var high = upper
        var lowValue = lowerValue
        for _ in 0 ..< 80 {
            let mid = (low + high) * 0.5
            let midValue = polynomialEvaluate(coefficients, at: mid)
            if abs(midValue) <= tolerance || high - low <= 1.0e-13 {
                return mid
            }
            if lowValue * midValue <= 0.0 {
                high = mid
            } else {
                low = mid
                lowValue = midValue
            }
        }
        return (low + high) * 0.5
    }

    private func trimmedPolynomial(_ coefficients: [Double]) -> [Double] {
        var trimmed = coefficients
        let tolerance = polynomialValueTolerance(coefficients)
        while trimmed.count > 1,
              abs(trimmed.last ?? 0.0) <= tolerance {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func polynomialValueTolerance(_ coefficients: [Double]) -> Double {
        max(1.0e-24, (coefficients.map { abs($0) }.max() ?? 0.0) * 1.0e-12)
    }

    private func cornerKnotSegmentBoundaries(
        _ controlPoints: [CADCore.Point2D]
    ) -> [Int] {
        let segmentCount = (controlPoints.count - 1) / 3
        guard segmentCount > 1 else {
            return []
        }

        var boundaries: [Int] = []
        for segmentBoundary in 1 ..< segmentCount {
            let knotIndex = segmentBoundary * 3
            let incoming = CADCore.Point2D(
                x: controlPoints[knotIndex].x - controlPoints[knotIndex - 1].x,
                y: controlPoints[knotIndex].y - controlPoints[knotIndex - 1].y
            )
            let outgoing = CADCore.Point2D(
                x: controlPoints[knotIndex + 1].x - controlPoints[knotIndex].x,
                y: controlPoints[knotIndex + 1].y - controlPoints[knotIndex].y
            )
            if isCornerBetweenSplineHandles(incoming: incoming, outgoing: outgoing) {
                boundaries.append(segmentBoundary)
            }
        }
        return boundaries
    }

    private func isCornerBetweenSplineHandles(
        incoming: CADCore.Point2D,
        outgoing: CADCore.Point2D
    ) -> Bool {
        let incomingLength = vectorLength(incoming)
        let outgoingLength = vectorLength(outgoing)
        let tinyLength = 1.0e-12
        guard incomingLength > tinyLength,
              outgoingLength > tinyLength else {
            return true
        }
        let dot = (incoming.x * outgoing.x + incoming.y * outgoing.y)
            / (incomingLength * outgoingLength)
        let clampedDot = min(max(dot, -1.0), 1.0)
        return clampedDot < cos(1.0e-4)
    }

    private func distance(
        _ first: CADCore.Point2D,
        _ second: CADCore.Point2D
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }

    private func vectorLength(_ vector: CADCore.Point2D) -> Double {
        sqrt(vector.x * vector.x + vector.y * vector.y)
    }

    private func mapOriginalKnotIfAligned(
        fraction: Double,
        originalSegmentCount: Int,
        rebuiltControlPointIndex: Int,
        into indexMap: inout [Int: Int]
    ) {
        let scaled = fraction * Double(originalSegmentCount)
        let rounded = scaled.rounded()
        guard abs(scaled - rounded) <= 1.0e-9 else {
            return
        }
        let segmentBoundary = Int(rounded)
        guard segmentBoundary >= 0,
              segmentBoundary <= originalSegmentCount else {
            return
        }
        indexMap[segmentBoundary * 3] = rebuiltControlPointIndex
    }

    private func resolvedSplineControlPoints(
        _ spline: SketchSpline,
        owner: String
    ) throws -> [CADCore.Point2D] {
        try spline.controlPoints.enumerated().map { index, point in
            let resolved = try resolvedPoint(
                point,
                owner: "\(owner) control point \(index + 1)"
            )
            return CADCore.Point2D(x: resolved.x, y: resolved.y)
        }
    }

    private func sketchSplineRebuildSample(
        on controlPoints: [CADCore.Point2D],
        fraction: Double,
        side: SketchSplineRebuildSampleSide
    ) throws -> SketchSplineRebuildSample {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve rebuild requires a cubic Bezier spline."
            )
        }

        let segmentCount = (controlPoints.count - 1) / 3
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let scaledFraction = clampedFraction * Double(segmentCount)
        let segmentIndex: Int
        let localFraction: Double
        let roundedFraction = scaledFraction.rounded()
        let knotTolerance = 1.0e-12
        if scaledFraction <= 0.0 {
            segmentIndex = 0
            localFraction = 0.0
        } else if scaledFraction >= Double(segmentCount) {
            segmentIndex = segmentCount - 1
            localFraction = 1.0
        } else if abs(scaledFraction - roundedFraction) <= knotTolerance {
            let boundary = Int(roundedFraction)
            switch side {
            case .before:
                segmentIndex = max(0, boundary - 1)
                localFraction = 1.0
            case .after:
                segmentIndex = min(segmentCount - 1, boundary)
                localFraction = 0.0
            }
        } else {
            segmentIndex = max(0, Int(floor(scaledFraction)))
            localFraction = scaledFraction - Double(segmentIndex)
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let localDerivative = cubicBezierDerivative(
            p0,
            p1,
            p2,
            p3,
            fraction: localFraction
        )
        return SketchSplineRebuildSample(
            point: cubicBezierPoint(
                p0,
                p1,
                p2,
                p3,
                fraction: localFraction
            ),
            derivative: CADCore.Point2D(
                x: localDerivative.x * Double(segmentCount),
                y: localDerivative.y * Double(segmentCount)
            )
        )
    }

    private func cubicBezierPoint(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        let inverseSquared = inverse * inverse
        let fractionSquared = fraction * fraction
        let inverseCubed = inverseSquared * inverse
        let fractionCubed = fractionSquared * fraction
        return CADCore.Point2D(
            x: inverseCubed * p0.x
                + 3.0 * inverseSquared * fraction * p1.x
                + 3.0 * inverse * fractionSquared * p2.x
                + fractionCubed * p3.x,
            y: inverseCubed * p0.y
                + 3.0 * inverseSquared * fraction * p1.y
                + 3.0 * inverse * fractionSquared * p2.y
                + fractionCubed * p3.y
        )
    }

    private func cubicBezierDerivative(
        _ p0: CADCore.Point2D,
        _ p1: CADCore.Point2D,
        _ p2: CADCore.Point2D,
        _ p3: CADCore.Point2D,
        fraction: Double
    ) -> CADCore.Point2D {
        let inverse = 1.0 - fraction
        return CADCore.Point2D(
            x: 3.0 * inverse * inverse * (p1.x - p0.x)
                + 6.0 * inverse * fraction * (p2.x - p1.x)
                + 3.0 * fraction * fraction * (p3.x - p2.x),
            y: 3.0 * inverse * inverse * (p1.y - p0.y)
                + 6.0 * inverse * fraction * (p2.y - p1.y)
                + 3.0 * fraction * fraction * (p3.y - p2.y)
        )
    }

    private func constraintsAfterSketchCurveRebuild(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchConstraint] {
        try constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        first,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    try rewriteSketchReferenceAfterCurveRebuild(
                        second,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    try rewriteSketchReferenceAfterCurveRebuild(
                        reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID else {
                    return constraint
                }
                if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                    return .smoothSplineControlPoint(entity: id, index: rebuiltIndex)
                }
                guard rebuilt.changesControlPointCount == false else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "internal smooth spline constraints when the point count changes"
                    )
                }
                return .smoothSplineControlPoint(entity: id, index: index)
            case .splineEndpointTangent:
                return constraint
            case .tangentSplineEndpoints:
                return constraint
            case .smoothSplineEndpoints(let first, let second):
                guard rebuilt.changesControlPointCount == false ||
                    (first.splineID != entityID && second.splineID != entityID) else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "smooth spline endpoint constraints when the point count changes"
                    )
                }
                return constraint
            case .horizontal(let id),
                 .vertical(let id):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline orientation constraints"
                    )
                }
                return constraint
            case .parallel(let first, let second),
                 .perpendicular(let first, let second),
                 .equalLength(let first, let second),
                 .tangent(let first, let second),
                 .concentric(let first, let second),
                 .equalRadius(let first, let second):
                guard first != entityID && second != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "whole-spline relationship constraints"
                    )
                }
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchCurveRebuild(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: try rewriteSketchReferenceAfterCurveRebuild(
                        from,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    to: try rewriteSketchReferenceAfterCurveRebuild(
                        to,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    value: value
                )
            case .radius(let id, _),
                 .diameter(let id, _):
                guard id != entityID else {
                    throw sketchCurveRebuildUnsupportedReference(
                        "circular dimensions"
                    )
                }
                return dimension
            }
        }
    }

    private func bridgeCurveSourcesAfterSketchCurveRebuild(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> [BridgeCurveSourceID: BridgeCurveSource] {
        var updated: [BridgeCurveSourceID: BridgeCurveSource] = [:]
        updated.reserveCapacity(sources.count)
        for (id, source) in sources {
            guard source.featureID != featureID || source.entityID != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "generated Bridge Curve source entities"
                )
            }
            updated[id] = BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.firstEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.firstEndpoint.parameter,
                    reversesSense: source.firstEndpoint.reversesSense,
                    tension: source.firstEndpoint.tension
                ),
                secondEndpoint: BridgeCurveEndpoint(
                    reference: try rewriteSketchReferenceAfterCurveRebuild(
                        source.secondEndpoint.reference,
                        entityID: entityID,
                        rebuilt: rebuilt
                    ),
                    parameter: source.secondEndpoint.parameter,
                    reversesSense: source.secondEndpoint.reversesSense,
                    tension: source.secondEndpoint.tension
                ),
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
        return updated
    }

    private func rewriteSketchReferenceAfterCurveRebuild(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        rebuilt: RebuiltSketchSpline
    ) throws -> SketchReference {
        switch reference {
        case .splineControlPoint(let id, let index) where id == entityID:
            guard index >= 0,
                  index < rebuilt.originalControlPointCount else {
                throw sketchCurveRebuildUnsupportedReference(
                    "out-of-range spline control-point references"
                )
            }
            if let rebuiltIndex = rebuilt.controlPointIndexMap[index] {
                return .splineControlPoint(
                    entity: entityID,
                    index: rebuiltIndex
                )
            }
            guard rebuilt.changesControlPointCount == false else {
                throw sketchCurveRebuildUnsupportedReference(
                    "internal spline control-point references when the point count changes"
                )
            }
            return reference
        case .splineControlPoint:
            return reference
        case .lineStart(let id),
             .lineEnd(let id),
             .entity(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id):
            guard id != entityID else {
                throw sketchCurveRebuildUnsupportedReference(
                    "incompatible point references"
                )
            }
            return reference
        }
    }

    private func sketchCurveRebuildUnsupportedReference(
        _ reason: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch curve rebuild cannot preserve \(reason) yet."
        )
    }

    private func constraintsAfterSketchCurveReverse(
        _ constraints: [SketchConstraint],
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [SketchConstraint] {
        constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second):
                return .coincident(
                    rewriteSketchReferenceAfterCurveReverse(
                        first,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    rewriteSketchReferenceAfterCurveReverse(
                        second,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    )
                )
            case .fixed(let reference):
                return .fixed(
                    rewriteSketchReferenceAfterCurveReverse(
                        reference,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    )
                )
            case .smoothSplineControlPoint(let id, let index):
                guard id == entityID,
                      let count = splineControlPointCount else {
                    return constraint
                }
                return .smoothSplineControlPoint(
                    entity: entityID,
                    index: reversedSplineControlPointIndex(index, controlPointCount: count)
                )
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                guard splineID == entityID else {
                    return constraint
                }
                return .splineEndpointTangent(
                    spline: splineID,
                    endpoint: reversedSplineEndpoint(endpoint),
                    line: lineID
                )
            case .tangentSplineEndpoints(let first, let second):
                return .tangentSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        second,
                        entityID: entityID
                    )
                )
            case .smoothSplineEndpoints(let first, let second):
                return .smoothSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveReverse(
                        first,
                        entityID: entityID
                    ),
                    second: rewriteSplineEndpointReferenceAfterCurveReverse(
                        second,
                        entityID: entityID
                    )
                )
            case .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius:
                return constraint
            }
        }
    }

    private func dimensionsAfterSketchCurveReverse(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteSketchReferenceAfterCurveReverse(
                        from,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    to: rewriteSketchReferenceAfterCurveReverse(
                        to,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteSketchReferenceAfterCurveReverse(
                        from,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    to: rewriteSketchReferenceAfterCurveReverse(
                        to,
                        entityID: entityID,
                        splineControlPointCount: splineControlPointCount
                    ),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private struct SketchLineJoinPlan {
        var retainedEntityID: SketchEntityID
        var removedEntityID: SketchEntityID
        var retainedOriginalLine: SketchLine
        var restoredOriginalLine: SketchLine
        var retainedLine: SketchLine
        var retainedSharedReference: SketchReference
        var removedSharedReference: SketchReference
        var removedOuterReference: SketchReference
        var migratedRemovedOuterReference: SketchReference
    }

    private struct SketchCurveGroupJoinPlan {
        var memberEntityIDs: [SketchEntityID]
        var firstJoinedReference: SketchReference
        var secondJoinedReference: SketchReference
        var continuity: SketchCurveJoinContinuity
    }

    private struct SketchCurveJoinEndpointSample {
        var reference: SketchReference
        var point: (x: Double, y: Double)
        var tangent: (x: Double, y: Double)
    }

    private func sketchLineJoinPlan(
        target: SelectionTarget,
        targetSelection: EditableSketchEntitySelection,
        adjacentTarget: SelectionTarget,
        adjacentSelection: EditableSketchEntitySelection
    ) throws -> SketchLineJoinPlan {
        guard targetSelection.featureID == adjacentSelection.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires both source curves to belong to the same sketch."
            )
        }
        guard targetSelection.entityID != adjacentSelection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves requires two distinct source curves."
            )
        }
        guard case .line(let targetLine) = targetSelection.entity,
              case .line(let adjacentLine) = adjacentSelection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves first source subset currently supports collinear source line pairs."
            )
        }

        let targetEndpointCandidates = try joinLineEndpointCandidates(
            target: target,
            selection: targetSelection,
            owner: "Join Curves target"
        )
        let adjacentEndpointCandidates = try joinLineEndpointCandidates(
            target: adjacentTarget,
            selection: adjacentSelection,
            owner: "Join Curves adjacent"
        )
        let linesAreCollinear = try joinLinesAreCollinear(
            targetLine,
            adjacentLine,
            owner: "Join Curves"
        )
        var hasAlignedEndpointPair = false
        var candidates: [SketchLineJoinPlan] = []
        for targetShared in targetEndpointCandidates {
            for adjacentShared in adjacentEndpointCandidates {
                if try joinLineEndpointsAreAligned(
                    targetShared,
                    adjacentShared,
                    sketch: targetSelection.sketch
                ) == false {
                    continue
                }
                hasAlignedEndpointPair = true
                if linesAreCollinear == false {
                    continue
                }
                let join = try sketchLineJoinPlan(
                    targetLine: targetLine,
                    targetEntityID: targetSelection.entityID,
                    targetSharedReference: targetShared,
                    adjacentLine: adjacentLine,
                    adjacentEntityID: adjacentSelection.entityID,
                    adjacentSharedReference: adjacentShared
                )
                candidates.append(join)
            }
        }

        guard candidates.count == 1,
              let join = candidates.first else {
            if candidates.isEmpty {
                if hasAlignedEndpointPair {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Join Curves requires selected source lines to be collinear."
                    )
                }
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves requires exactly one aligned endpoint pair between the selected source lines."
                )
            }
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves found multiple aligned endpoint pairs; select explicit endpoints to disambiguate."
            )
        }
        _ = try resolvedLineMetrics(join.retainedLine, owner: "Join Curves result")
        return join
    }

    private func sketchCurveGroupJoinPlan(
        target: SelectionTarget,
        targetSelection: EditableSketchEntitySelection,
        adjacentTarget: SelectionTarget,
        adjacentSelection: EditableSketchEntitySelection,
        continuity: SketchCurveJoinContinuity
    ) throws -> SketchCurveGroupJoinPlan {
        guard targetSelection.featureID == adjacentSelection.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires both source curves to belong to the same sketch."
            )
        }
        guard targetSelection.entityID != adjacentSelection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves requires two distinct source curves."
            )
        }
        let targetEndpointCandidates = try joinCurveEndpointCandidates(
            target: target,
            selection: targetSelection,
            owner: "Join Curves target"
        )
        let adjacentEndpointCandidates = try joinCurveEndpointCandidates(
            target: adjacentTarget,
            selection: adjacentSelection,
            owner: "Join Curves adjacent"
        )
        var candidates: [SketchCurveGroupJoinPlan] = []
        for targetReference in targetEndpointCandidates {
            for adjacentReference in adjacentEndpointCandidates {
                guard try joinCurveEndpointsAreAligned(
                    targetReference,
                    adjacentReference,
                    sketch: targetSelection.sketch
                ) else {
                    continue
                }
                candidates.append(
                    SketchCurveGroupJoinPlan(
                        memberEntityIDs: [
                            targetSelection.entityID,
                            adjacentSelection.entityID,
                        ],
                        firstJoinedReference: targetReference,
                        secondJoinedReference: adjacentReference,
                        continuity: continuity
                    )
                )
            }
        }
        guard candidates.count == 1,
              let join = candidates.first else {
            if candidates.isEmpty {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves requires exactly one aligned endpoint pair between the selected source curves."
                )
            }
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves found multiple aligned endpoint pairs; select explicit endpoints to disambiguate."
            )
        }
        try validateSketchCurveGroupJoinContinuity(join, sketch: targetSelection.sketch)
        return join
    }

    private func joinLineEndpointCandidates(
        target: SelectionTarget,
        selection: EditableSketchEntitySelection,
        owner: String
    ) throws -> [SketchReference] {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a source line or source line endpoint target."
            )
        }
        if let handleReference = componentID.sketchPointHandleReference {
            guard handleReference.featureID == selection.featureID,
                  handleReference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) endpoint target does not match the selected source line."
                )
            }
            switch handleReference.handle {
            case .lineStart:
                return [.lineStart(selection.entityID)]
            case .lineEnd:
                return [.lineEnd(selection.entityID)]
            case .point,
                 .circleCenter,
                 .arcCenter,
                 .arcStart,
                 .arcEnd:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a source line endpoint target."
                )
            }
        }
        guard let entityReference = componentID.sketchEntityReference,
              entityReference.featureID == selection.featureID,
              entityReference.entityID == selection.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a source line entity target."
            )
        }
        return [
            .lineStart(selection.entityID),
            .lineEnd(selection.entityID),
        ]
    }

    private func joinCurveEndpointCandidates(
        target: SelectionTarget,
        selection: EditableSketchEntitySelection,
        owner: String
    ) throws -> [SketchReference] {
        guard case .sketchEntity(let componentID) = target.component else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a source line, arc, or endpoint target."
            )
        }
        if let handleReference = componentID.sketchPointHandleReference {
            guard handleReference.featureID == selection.featureID,
                  handleReference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) endpoint target does not match the selected source curve."
                )
            }
            return [
                try joinCurveEndpointReference(
                    handleReference.handle,
                    selection: selection,
                    owner: owner
                ),
            ]
        }
        guard let entityReference = componentID.sketchEntityReference,
              entityReference.featureID == selection.featureID,
              entityReference.entityID == selection.entityID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a source line or arc entity target."
            )
        }
        switch selection.entity {
        case .line:
            return [
                .lineStart(selection.entityID),
                .lineEnd(selection.entityID),
            ]
        case .arc:
            return [
                .arcStart(selection.entityID),
                .arcEnd(selection.entityID),
            ]
        case .point,
             .circle,
             .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves composite join currently supports source line and arc endpoints."
            )
        }
    }

    private func joinCurveEndpointReference(
        _ handle: SketchEntityPointHandle,
        selection: EditableSketchEntitySelection,
        owner: String
    ) throws -> SketchReference {
        switch selection.entity {
        case .line:
            switch handle {
            case .lineStart:
                return .lineStart(selection.entityID)
            case .lineEnd:
                return .lineEnd(selection.entityID)
            case .point,
                 .circleCenter,
                 .arcCenter,
                 .arcStart,
                 .arcEnd:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a source line endpoint target."
                )
            }
        case .arc:
            switch handle {
            case .arcStart:
                return .arcStart(selection.entityID)
            case .arcEnd:
                return .arcEnd(selection.entityID)
            case .point,
                 .lineStart,
                 .lineEnd,
                 .circleCenter,
                 .arcCenter:
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a source arc endpoint target."
                )
            }
        case .point,
             .circle,
             .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves composite join currently supports source line and arc endpoints."
            )
        }
    }

    private func joinLineEndpointsAreAligned(
        _ first: SketchReference,
        _ second: SketchReference,
        sketch: Sketch
    ) throws -> Bool {
        guard let firstPoint = try resolvedPoint(first, in: sketch, owner: "Join Curves endpoint"),
              let secondPoint = try resolvedPoint(second, in: sketch, owner: "Join Curves endpoint") else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires source line endpoint references."
            )
        }
        return squaredDistance(firstPoint, secondPoint) <= joinCurveEndpointToleranceSquared
    }

    private func joinCurveEndpointsAreAligned(
        _ first: SketchReference,
        _ second: SketchReference,
        sketch: Sketch
    ) throws -> Bool {
        guard let firstPoint = try resolvedPoint(first, in: sketch, owner: "Join Curves endpoint"),
              let secondPoint = try resolvedPoint(second, in: sketch, owner: "Join Curves endpoint") else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires source curve endpoint references."
            )
        }
        return squaredDistance(firstPoint, secondPoint) <= joinCurveEndpointToleranceSquared
    }

    private func validateSketchCurveGroupJoinContinuity(
        _ join: SketchCurveGroupJoinPlan,
        sketch: Sketch
    ) throws {
        switch join.continuity {
        case .g0:
            return
        case .g1:
            guard try joinCurveGroupTangentConstraint(join, sketch: sketch) != nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves G1 continuity currently requires one source line endpoint and one source arc endpoint."
                )
            }
            let firstSample = try joinCurveEndpointSample(
                join.firstJoinedReference,
                sketch: sketch,
                owner: "Join Curves first continuity"
            )
            let secondSample = try joinCurveEndpointSample(
                join.secondJoinedReference,
                sketch: sketch,
                owner: "Join Curves second continuity"
            )
            let tangentAngle = joinCurveTangentAngle(
                firstSample.tangent,
                secondSample.tangent,
                allowsReversedDirection: true
            )
            guard tangentAngle <= joinCurveTangentTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves G1 continuity requires the selected endpoints to already be tangent."
                )
            }
        case .g2:
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves G2 continuity requires a source curve continuity solver that is not implemented yet."
            )
        }
    }

    private func joinCurveEndpointSample(
        _ reference: SketchReference,
        sketch: Sketch,
        owner: String
    ) throws -> SketchCurveJoinEndpointSample {
        let sampler = SketchCurveSampler(samplesPerSegment: 1)
        switch reference {
        case .lineStart(let entityID),
             .lineEnd(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line = entity,
                  let start = try resolvedPoint(.lineStart(entityID), in: sketch, owner: owner),
                  let end = try resolvedPoint(.lineEnd(entityID), in: sketch, owner: owner),
                  let sample = sampler.lineSample(
                    start: CADCore.Point2D(x: start.x, y: start.y),
                    end: CADCore.Point2D(x: end.x, y: end.y),
                    parameter: reference == .lineStart(entityID) ? 0.0 : 1.0
                  ) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) requires a non-degenerate source line endpoint."
                )
            }
            return SketchCurveJoinEndpointSample(
                reference: reference,
                point: (x: sample.point.x, y: sample.point.y),
                tangent: (x: sample.tangent.x, y: sample.tangent.y)
            )
        case .arcStart(let entityID),
             .arcEnd(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .arc(let arc) = entity else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) requires a source arc endpoint."
                )
            }
            let center = try resolvedPoint(arc.center, owner: owner)
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
            guard let sample = sampler.arcSample(
                center: CADCore.Point2D(x: center.x, y: center.y),
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                parameter: reference == .arcStart(entityID) ? 0.0 : 1.0
            ) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) requires a non-degenerate source arc endpoint."
                )
            }
            return SketchCurveJoinEndpointSample(
                reference: reference,
                point: (x: sample.point.x, y: sample.point.y),
                tangent: (x: sample.tangent.x, y: sample.tangent.y)
            )
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a source line or arc endpoint."
            )
        }
    }

    private var joinCurveTangentTolerance: Double {
        max(ModelingTolerance.standard.angle, 1.0e-4)
    }

    private func joinCurveTangentAngle(
        _ first: (x: Double, y: Double),
        _ second: (x: Double, y: Double),
        allowsReversedDirection: Bool
    ) -> Double {
        let dot = min(max(first.x * second.x + first.y * second.y, -1.0), 1.0)
        let angle = acos(dot)
        guard allowsReversedDirection else {
            return angle
        }
        return min(angle, abs(Double.pi - angle))
    }

    private var joinCurveEndpointToleranceSquared: Double {
        let tolerance = max(ModelingTolerance.standard.distance, 1.0e-12)
        return tolerance * tolerance
    }

    private func joinLinesAreCollinear(
        _ first: SketchLine,
        _ second: SketchLine,
        owner: String
    ) throws -> Bool {
        let firstStart = try resolvedPoint(first.start, owner: "\(owner) first start")
        let firstEnd = try resolvedPoint(first.end, owner: "\(owner) first end")
        let secondStart = try resolvedPoint(second.start, owner: "\(owner) second start")
        let secondEnd = try resolvedPoint(second.end, owner: "\(owner) second end")
        let firstX = firstEnd.x - firstStart.x
        let firstY = firstEnd.y - firstStart.y
        let secondX = secondEnd.x - secondStart.x
        let secondY = secondEnd.y - secondStart.y
        let firstLength = hypot(firstX, firstY)
        let secondLength = hypot(secondX, secondY)
        guard firstLength > ModelingTolerance.standard.distance,
              secondLength > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires non-zero source line lengths."
            )
        }
        let cross = firstX * secondY - firstY * secondX
        return abs(cross) <= max(1.0e-12, firstLength * secondLength * 1.0e-9)
    }

    private func sketchLineJoinPlan(
        targetLine: SketchLine,
        targetEntityID: SketchEntityID,
        targetSharedReference: SketchReference,
        adjacentLine: SketchLine,
        adjacentEntityID: SketchEntityID,
        adjacentSharedReference: SketchReference
    ) throws -> SketchLineJoinPlan {
        let adjacentOuterReference = try oppositeJoinLineEndpoint(
            adjacentSharedReference,
            entityID: adjacentEntityID,
            owner: "Join Curves adjacent"
        )
        let adjacentOuterPoint = try sketchLinePoint(
            adjacentLine,
            reference: adjacentOuterReference,
            owner: "Join Curves adjacent"
        )

        switch targetSharedReference {
        case .lineStart(let id) where id == targetEntityID:
            return SketchLineJoinPlan(
                retainedEntityID: targetEntityID,
                removedEntityID: adjacentEntityID,
                retainedOriginalLine: targetLine,
                restoredOriginalLine: adjacentLine,
                retainedLine: SketchLine(start: adjacentOuterPoint, end: targetLine.end),
                retainedSharedReference: targetSharedReference,
                removedSharedReference: adjacentSharedReference,
                removedOuterReference: adjacentOuterReference,
                migratedRemovedOuterReference: .lineStart(targetEntityID)
            )
        case .lineEnd(let id) where id == targetEntityID:
            return SketchLineJoinPlan(
                retainedEntityID: targetEntityID,
                removedEntityID: adjacentEntityID,
                retainedOriginalLine: targetLine,
                restoredOriginalLine: adjacentLine,
                retainedLine: SketchLine(start: targetLine.start, end: adjacentOuterPoint),
                retainedSharedReference: targetSharedReference,
                removedSharedReference: adjacentSharedReference,
                removedOuterReference: adjacentOuterReference,
                migratedRemovedOuterReference: .lineEnd(targetEntityID)
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves target endpoint must be a source line endpoint."
            )
        }
    }

    private func oppositeJoinLineEndpoint(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        owner: String
    ) throws -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .lineEnd(entityID)
        case .lineEnd(let id) where id == entityID:
            return .lineStart(entityID)
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint must be a source line endpoint."
            )
        }
    }

    private func sketchLinePoint(
        _ line: SketchLine,
        reference: SketchReference,
        owner: String
    ) throws -> SketchPoint {
        switch reference {
        case .lineStart:
            return line.start
        case .lineEnd:
            return line.end
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a source line endpoint."
            )
        }
    }

    private func validateSketchLineJoin(
        _ join: SketchLineJoinPlan,
        sketch: Sketch,
        featureID: FeatureID
    ) throws {
        let affectedEntityIDs: Set<SketchEntityID> = [
            join.retainedEntityID,
            join.removedEntityID,
        ]
        for source in productMetadata.joinedCurveSources.values where source.featureID == featureID {
            guard affectedEntityIDs.contains(source.retainedEntityID) == false,
                  affectedEntityIDs.contains(source.restoredEntityID) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot join curves that already carry joined-curve ownership metadata."
                )
            }
        }
        for source in productMetadata.joinedCurveGroupSources.values where source.featureID == featureID {
            guard source.memberEntityIDs.allSatisfy({ affectedEntityIDs.contains($0) == false }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot join curves that already carry joined-curve ownership metadata."
                )
            }
        }
        for source in productMetadata.bridgeCurveSources.values where source.featureID == featureID {
            guard bridgeEndpointReferencesAnyJoinEntity(source.firstEndpoint, affectedEntityIDs: affectedEntityIDs) == false,
                  bridgeEndpointReferencesAnyJoinEntity(source.secondEndpoint, affectedEntityIDs: affectedEntityIDs) == false,
                  source.entityID != join.retainedEntityID,
                  source.entityID != join.removedEntityID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot preserve generated Bridge Curve source metadata for joined lines yet."
                )
            }
        }
        _ = try constraintsAfterSketchLineJoin(sketch.constraints, join: join)
        _ = try dimensionsAfterSketchLineJoin(sketch.dimensions, join: join)
    }

    private func validateSketchCurveGroupJoin(
        _ join: SketchCurveGroupJoinPlan,
        sketch: Sketch,
        featureID: FeatureID
    ) throws {
        let affectedEntityIDs = Set(join.memberEntityIDs)
        for source in productMetadata.joinedCurveSources.values where source.featureID == featureID {
            guard affectedEntityIDs.contains(source.retainedEntityID) == false,
                  affectedEntityIDs.contains(source.restoredEntityID) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot join curves that already carry joined-curve ownership metadata."
                )
            }
        }
        for source in productMetadata.joinedCurveGroupSources.values where source.featureID == featureID {
            guard source.memberEntityIDs.allSatisfy({ affectedEntityIDs.contains($0) == false }) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot join curves that already carry joined-curve ownership metadata."
                )
            }
        }
        for source in productMetadata.bridgeCurveSources.values where source.featureID == featureID {
            guard bridgeEndpointReferencesAnyJoinEntity(source.firstEndpoint, affectedEntityIDs: affectedEntityIDs) == false,
                  bridgeEndpointReferencesAnyJoinEntity(source.secondEndpoint, affectedEntityIDs: affectedEntityIDs) == false,
                  affectedEntityIDs.contains(source.entityID) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves cannot preserve generated Bridge Curve source metadata for joined curves yet."
                )
            }
        }
        guard sketch.entities.keys.contains(join.memberEntityIDs[0]),
              sketch.entities.keys.contains(join.memberEntityIDs[1]) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires existing source curve entities."
            )
        }
    }

    private func bridgeEndpointReferencesAnyJoinEntity(
        _ endpoint: BridgeCurveEndpoint,
        affectedEntityIDs: Set<SketchEntityID>
    ) -> Bool {
        affectedEntityIDs.contains(where: { entityID in
            bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID)
        })
    }

    private func constraintsAfterSketchLineJoin(
        _ constraints: [SketchConstraint],
        join: SketchLineJoinPlan
    ) throws -> [SketchConstraint] {
        var updated: [SketchConstraint] = []
        for constraint in constraints {
            if joinConstraintIsSharedEndpointCoincidence(constraint, join: join) {
                continue
            }
            switch constraint {
            case .coincident(let first, let second):
                updated.append(.coincident(
                    try rewriteSketchReferenceAfterLineJoin(first, join: join),
                    try rewriteSketchReferenceAfterLineJoin(second, join: join)
                ))
            case .fixed(let reference):
                updated.append(.fixed(try rewriteSketchReferenceAfterLineJoin(reference, join: join)))
            case .horizontal(let entityID):
                updated.append(.horizontal(entityID == join.removedEntityID ? join.retainedEntityID : entityID))
            case .vertical(let entityID):
                updated.append(.vertical(entityID == join.removedEntityID ? join.retainedEntityID : entityID))
            case .parallel(let first, let second):
                try rejectSketchLineJoinWholeLineConstraintIfNeeded(
                    first,
                    second,
                    join: join,
                    message: "Join Curves cannot preserve removed-line parallel constraints yet."
                )
                updated.append(constraint)
            case .perpendicular(let first, let second):
                try rejectSketchLineJoinWholeLineConstraintIfNeeded(
                    first,
                    second,
                    join: join,
                    message: "Join Curves cannot preserve removed-line perpendicular constraints yet."
                )
                updated.append(constraint)
            case .equalLength(let first, let second):
                if first == join.retainedEntityID || first == join.removedEntityID ||
                    second == join.retainedEntityID || second == join.removedEntityID {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Join Curves cannot preserve equal-length constraints on joined lines."
                    )
                }
                updated.append(constraint)
            case .tangent(let first, let second):
                try rejectSketchLineJoinWholeLineConstraintIfNeeded(
                    first,
                    second,
                    join: join,
                    message: "Join Curves cannot preserve removed-line tangent constraints yet."
                )
                updated.append(constraint)
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                guard lineID != join.removedEntityID else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Join Curves cannot preserve removed-line spline tangent constraints yet."
                    )
                }
                updated.append(.splineEndpointTangent(spline: splineID, endpoint: endpoint, line: lineID))
            case .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints:
                updated.append(constraint)
            }
        }
        return updated
    }

    private func constraintsAfterSketchCurveGroupJoin(
        _ constraints: [SketchConstraint],
        join: SketchCurveGroupJoinPlan,
        sketch: Sketch
    ) throws -> [SketchConstraint] {
        var updated = constraints
        if updated.contains(where: { constraint in
            joinConstraintMatchesEndpoints(
                constraint,
                first: join.firstJoinedReference,
                second: join.secondJoinedReference
            )
        }) == false {
            updated.append(.coincident(join.firstJoinedReference, join.secondJoinedReference))
        }
        if join.continuity == .g1,
           let tangentConstraint = try joinCurveGroupTangentConstraint(join, sketch: sketch),
           updated.contains(where: { constraint in
               joinConstraintMatchesTangentEntities(constraint, tangentConstraint: tangentConstraint)
           }) == false {
            updated.append(tangentConstraint)
        }
        return updated
    }

    private func joinConstraintMatchesEndpoints(
        _ constraint: SketchConstraint,
        first: SketchReference,
        second: SketchReference
    ) -> Bool {
        guard case .coincident(let existingFirst, let existingSecond) = constraint else {
            return false
        }
        return (existingFirst == first && existingSecond == second) ||
            (existingFirst == second && existingSecond == first)
    }

    private func joinCurveGroupTangentConstraint(
        _ join: SketchCurveGroupJoinPlan,
        sketch: Sketch
    ) throws -> SketchConstraint? {
        guard let firstEntityID = joinedCurveReferenceEntityID(join.firstJoinedReference),
              let secondEntityID = joinedCurveReferenceEntityID(join.secondJoinedReference),
              let firstEntity = sketch.entities[firstEntityID],
              let secondEntity = sketch.entities[secondEntityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves continuity requires existing source curve entities."
            )
        }
        switch (firstEntity, secondEntity) {
        case (.line, .arc):
            return .tangent(firstEntityID, secondEntityID)
        case (.arc, .line):
            return .tangent(secondEntityID, firstEntityID)
        case (.line, .line),
             (.arc, .arc),
             (.point, _),
             (.circle, _),
             (.spline, _),
             (_, .point),
             (_, .circle),
             (_, .spline):
            return nil
        }
    }

    private func joinConstraintMatchesTangentEntities(
        _ constraint: SketchConstraint,
        tangentConstraint: SketchConstraint
    ) -> Bool {
        guard case .tangent(let first, let second) = constraint,
              case .tangent(let tangentFirst, let tangentSecond) = tangentConstraint else {
            return false
        }
        return (first == tangentFirst && second == tangentSecond) ||
            (first == tangentSecond && second == tangentFirst)
    }

    private func joinedCurveReferenceEntityID(_ reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case .lineStart(let entityID),
             .lineEnd(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID):
            return entityID
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func dimensionsAfterSketchLineJoin(
        _ dimensions: [SketchDimension],
        join: SketchLineJoinPlan
    ) throws -> [SketchDimension] {
        try dimensions.map { dimension in
            switch dimension {
            case .distance(let first, let second, let value):
                return .distance(
                    from: try rewriteSketchReferenceAfterLineJoin(first, join: join),
                    to: try rewriteSketchReferenceAfterLineJoin(second, join: join),
                    value: value
                )
            case .angle(let first, let second, let value):
                return .angle(
                    from: try rewriteSketchReferenceAfterLineJoin(first, join: join),
                    to: try rewriteSketchReferenceAfterLineJoin(second, join: join),
                    value: value
                )
            case .radius(let entityID, _):
                if entityID == join.removedEntityID {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Join Curves cannot preserve circular dimensions on removed joined entities."
                    )
                }
                return dimension
            case .diameter(let entityID, _):
                if entityID == join.removedEntityID {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Join Curves cannot preserve circular dimensions on removed joined entities."
                    )
                }
                return dimension
            }
        }
    }

    private func rejectSketchLineJoinWholeLineConstraintIfNeeded(
        _ first: SketchEntityID,
        _ second: SketchEntityID,
        join: SketchLineJoinPlan,
        message: String
    ) throws {
        if first == join.removedEntityID || second == join.removedEntityID {
            throw EditorError(code: .commandInvalid, message: message)
        }
    }

    private func joinConstraintIsSharedEndpointCoincidence(
        _ constraint: SketchConstraint,
        join: SketchLineJoinPlan
    ) -> Bool {
        guard case .coincident(let first, let second) = constraint else {
            return false
        }
        return (first == join.retainedSharedReference && second == join.removedSharedReference) ||
            (first == join.removedSharedReference && second == join.retainedSharedReference)
    }

    private func rewriteSketchReferenceAfterLineJoin(
        _ reference: SketchReference,
        join: SketchLineJoinPlan
    ) throws -> SketchReference {
        if reference == join.retainedSharedReference || reference == join.removedSharedReference {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves cannot preserve dimensions or constraints attached to the joined interior endpoint."
            )
        }
        if reference == join.removedOuterReference {
            return join.migratedRemovedOuterReference
        }
        if sketchReference(reference, references: join.removedEntityID) {
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves cannot preserve whole-curve references to the removed joined line yet."
            )
        }
        return reference
    }

    private func joinedCurveSourceIfPresent(
        for selection: EditableSketchEntitySelection
    ) throws -> JoinedCurveSource? {
        let matches = productMetadata.joinedCurveSources.values.filter { source in
            source.featureID == selection.featureID &&
                source.retainedEntityID == selection.entityID
        }
        guard matches.count <= 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve found duplicate joined-curve ownership metadata for the selected source curve."
            )
        }
        return matches.first
    }

    private func joinedCurveGroupSourceIfPresent(
        for selection: EditableSketchEntitySelection
    ) throws -> JoinedCurveGroupSource? {
        let matches = productMetadata.joinedCurveGroupSources.values.filter { source in
            source.featureID == selection.featureID &&
                source.memberEntityIDs.contains(selection.entityID)
        }
        guard matches.count <= 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve found duplicate joined-curve ownership metadata for the selected source curve."
            )
        }
        return matches.first
    }

    private func validateSketchLineUnjoin(
        _ source: JoinedCurveSource,
        currentLine: SketchLine,
        sketch: Sketch
    ) throws {
        guard sketch.entities[source.restoredEntityID] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a source line because its original entity ID is already in use."
            )
        }
        guard try sketchLinesMatch(
            currentLine,
            source.joinedLine,
            owner: "Unjoin Curve joined line"
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a joined line after its geometry changed."
            )
        }
        guard sketch.constraints == source.constraintsAfterJoin,
              sketch.dimensions == source.dimensionsAfterJoin else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a joined line after its constraints or dimensions changed."
            )
        }
        for bridgeSource in productMetadata.bridgeCurveSources.values where bridgeSource.featureID == source.featureID {
            guard bridgeEndpointReferencesEntity(bridgeSource.firstEndpoint, entityID: source.retainedEntityID) == false,
                  bridgeEndpointReferencesEntity(bridgeSource.secondEndpoint, entityID: source.retainedEntityID) == false,
                  bridgeSource.entityID != source.retainedEntityID else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Unjoin Curve cannot preserve generated Bridge Curve source metadata for joined lines yet."
                )
            }
        }
        _ = try resolvedLineMetrics(source.retainedOriginalLine, owner: "Unjoin Curve retained result")
        _ = try resolvedLineMetrics(source.restoredOriginalLine, owner: "Unjoin Curve restored result")
    }

    private func validateSketchCurveGroupUnjoin(
        _ source: JoinedCurveGroupSource,
        sketch: Sketch
    ) throws {
        for entityID in source.memberEntityIDs {
            guard sketch.entities[entityID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Unjoin Curve cannot restore a joined curve group after a member source curve was removed."
                )
            }
        }
        guard sketch.constraints == source.constraintsAfterJoin,
              sketch.dimensions == source.dimensionsAfterJoin else {
            throw EditorError(
                code: .commandInvalid,
                message: "Unjoin Curve cannot restore a joined curve group after its constraints or dimensions changed."
            )
        }
        let affectedEntityIDs = Set(source.memberEntityIDs)
        for bridgeSource in productMetadata.bridgeCurveSources.values where bridgeSource.featureID == source.featureID {
            guard bridgeEndpointReferencesAnyJoinEntity(
                bridgeSource.firstEndpoint,
                affectedEntityIDs: affectedEntityIDs
            ) == false,
            bridgeEndpointReferencesAnyJoinEntity(
                bridgeSource.secondEndpoint,
                affectedEntityIDs: affectedEntityIDs
            ) == false,
            affectedEntityIDs.contains(bridgeSource.entityID) == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Unjoin Curve cannot preserve generated Bridge Curve source metadata for joined curves yet."
                )
            }
        }
    }

    private func sketchLinesMatch(
        _ first: SketchLine,
        _ second: SketchLine,
        owner: String
    ) throws -> Bool {
        let firstStart = try resolvedPoint(first.start, owner: "\(owner) first start")
        let firstEnd = try resolvedPoint(first.end, owner: "\(owner) first end")
        let secondStart = try resolvedPoint(second.start, owner: "\(owner) second start")
        let secondEnd = try resolvedPoint(second.end, owner: "\(owner) second end")
        return squaredDistance(firstStart, secondStart) <= joinCurveEndpointToleranceSquared &&
            squaredDistance(firstEnd, secondEnd) <= joinCurveEndpointToleranceSquared
    }

    private struct SketchCurveSegmentSplitResult {
        var originalEntityID: SketchEntityID
        var newEntityID: SketchEntityID
        var fraction: Double
        var retainedEntity: SketchEntity
        var newEntity: SketchEntity
        var insertedRetainedReference: SketchReference
        var insertedNewReference: SketchReference
        var originalEndReference: SketchReference
        var migratedEndReference: SketchReference
    }

    private func validateSketchCurveCanSplit(
        selection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        )
    ) throws {
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split cannot split a generated Bridge Curve source."
            )
        }

        switch selection.entity {
        case .line:
            break
        case .spline(let spline):
            guard spline.isClosed == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch curve split requires an open spline curve."
                )
            }
        case .arc:
            break
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split requires an open line, arc, or spline curve; circles do not expose a split segment."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch curve split requires a line, arc, or spline curve target."
            )
        }

        for constraint in selection.sketch.constraints {
            try validateConstraintCanSplitSketchCurve(
                constraint,
                entityID: selection.entityID,
                entity: selection.entity
            )
        }
        for dimension in selection.sketch.dimensions {
            try validateDimensionCanSplitSketchCurve(
                dimension,
                entityID: selection.entityID,
                entity: selection.entity
            )
        }
    }

    private func validateConstraintCanSplitSketchCurve(
        _ constraint: SketchConstraint,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        switch constraint {
        case .coincident(let first, let second):
            try validateSketchReferenceCanSplit(first, entityID: entityID, entity: entity)
            try validateSketchReferenceCanSplit(second, entityID: entityID, entity: entity)
        case .fixed(let reference):
            try validateSketchReferenceCanSplit(reference, entityID: entityID, entity: entity)
        case .horizontal(let id),
             .vertical(let id):
            if id == entityID, case .spline = entity {
                throw sketchCurveSplitUnsupportedConstraint("spline orientation constraints")
            }
        case .parallel(let first, let second),
             .perpendicular(let first, let second):
            if first == entityID || second == entityID,
               case .spline = entity {
                throw sketchCurveSplitUnsupportedConstraint("spline line relationship constraints")
            }
        case .equalLength(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("equal-length constraints")
            }
        case .tangent(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("curve tangent constraints")
            }
        case .concentric(let first, let second),
             .equalRadius(let first, let second):
            if first == entityID || second == entityID {
                throw sketchCurveSplitUnsupportedConstraint("circular constraints")
            }
        case .smoothSplineControlPoint(let id, _):
            if id == entityID {
                throw sketchCurveSplitUnsupportedConstraint("internal spline smooth constraints")
            }
        case .splineEndpointTangent:
            return
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            try validateSplineEndpointReferenceCanSplit(first, entityID: entityID, entity: entity)
            try validateSplineEndpointReferenceCanSplit(second, entityID: entityID, entity: entity)
        }
    }

    private func validateDimensionCanSplitSketchCurve(
        _ dimension: SketchDimension,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            try validateSketchReferenceCanSplit(from, entityID: entityID, entity: entity)
            try validateSketchReferenceCanSplit(to, entityID: entityID, entity: entity)
        case .radius(let id, _),
             .diameter(let id, _):
            if id == entityID {
                throw sketchCurveSplitUnsupportedConstraint("circular dimensions")
            }
        }
    }

    private func validateSketchReferenceCanSplit(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        guard sketchReference(reference, references: entityID) else {
            return
        }
        switch (reference, entity) {
        case (.lineStart(let id), .line) where id == entityID:
            return
        case (.lineEnd(let id), .line) where id == entityID:
            return
        case (.arcStart(let id), .arc) where id == entityID:
            return
        case (.arcEnd(let id), .arc) where id == entityID:
            return
        case (.splineControlPoint(let id, let index), .spline(let spline)) where id == entityID:
            guard index == 0 || index == spline.controlPoints.count - 1 else {
                throw sketchCurveSplitUnsupportedConstraint("internal spline control-point references")
            }
        default:
            throw sketchCurveSplitUnsupportedConstraint("entity-level or incompatible references")
        }
    }

    private func validateSplineEndpointReferenceCanSplit(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID,
        entity: SketchEntity
    ) throws {
        guard reference.splineID == entityID else {
            return
        }
        guard case .spline = entity else {
            throw sketchCurveSplitUnsupportedConstraint("incompatible spline endpoint references")
        }
    }

    private func sketchCurveSplitUnsupportedConstraint(_ reason: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch curve split cannot preserve \(reason) yet."
        )
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

    func sketchConstraint(
        _ constraint: SketchConstraint,
        references entityID: SketchEntityID
    ) -> Bool {
        switch constraint {
        case .coincident(let first, let second):
            return sketchReference(first, references: entityID) ||
                sketchReference(second, references: entityID)
        case .fixed(let reference):
            return sketchReference(reference, references: entityID)
        case .horizontal(let id),
             .vertical(let id),
             .smoothSplineControlPoint(let id, _):
            return id == entityID
        case .parallel(let first, let second),
             .perpendicular(let first, let second),
             .equalLength(let first, let second),
             .tangent(let first, let second),
             .concentric(let first, let second),
             .equalRadius(let first, let second):
            return first == entityID || second == entityID
        case .splineEndpointTangent(let splineID, _, let lineID):
            return splineID == entityID || lineID == entityID
        case .tangentSplineEndpoints(let first, let second),
             .smoothSplineEndpoints(let first, let second):
            return first.splineID == entityID || second.splineID == entityID
        }
    }

    func sketchDimension(
        _ dimension: SketchDimension,
        references entityID: SketchEntityID
    ) -> Bool {
        switch dimension {
        case .distance(let from, let to, _),
             .angle(let from, let to, _):
            return sketchReference(from, references: entityID) ||
                sketchReference(to, references: entityID)
        case .radius(let id, _),
             .diameter(let id, _):
            return id == entityID
        }
    }

    private struct CutCurveLineSegment {
        var startX: Double
        var startY: Double
        var endX: Double
        var endY: Double
    }

    private struct CutCurveCircle {
        var centerX: Double
        var centerY: Double
        var radius: Double
    }

    private struct CutCurveArc {
        var circle: CutCurveCircle
        var startAngle: Double
        var endAngle: Double
    }

    private static let cutCurveSplineSamplesPerSegment = 64
    private typealias CutCurveSplineSampleSegment = (
        start: CurveEvaluationSample,
        end: CurveEvaluationSample
    )

    private func cutSketchCurveFractions(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws -> [Double] {
        try validateCutSketchCurveSelections(
            targetSelection: targetSelection,
            cutterSelection: cutterSelection,
            options: options
        )
        let fractions: [Double]
        switch targetSelection.entity {
        case .line(let targetLine):
            let target = try resolvedCutCurveLineSegment(targetLine, owner: "Cut Curve target")
            fractions = try cutFractionsForLineTarget(
                target: target,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .arc(let targetArc):
            let target = try resolvedCutCurveArc(targetArc, owner: "Cut Curve target")
            fractions = try cutFractionsForArcTarget(
                target: target,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .spline(let targetSpline):
            let samples = try resolvedCutCurveSplineSamples(
                targetSpline,
                owner: "Cut Curve target"
            )
            fractions = try cutFractionsForSplineTarget(
                samples: samples,
                cutterSelection: cutterSelection,
                extendsCutter: options.extendsCutter
            )
        case .point, .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, arc, or open spline target curve."
            )
        }
        let uniqueFractions = uniqueInteriorCutFractions(fractions)
        guard uniqueFractions.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not intersect the target curve inside the supported target segment."
            )
        }
        return uniqueFractions
    }

    private func cutFractionsForLineTarget(
        target: CutCurveLineSegment,
        cutterSelection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        ),
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            return try cutFractionsForLineLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return cutFractionsForLineCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return cutFractionsForLineCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: extendsCutter ? nil : cutter
            )
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            return cutFractionsForLineSplineIntersection(
                target: target,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
    }

    private func cutFractionsForSplineTarget(
        samples: [CurveEvaluationSample],
        cutterSelection: EditableSketchEntitySelection,
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            var rejectedByCutterReach = false
            var fractions: [Double] = []
            for segment in cutCurveSplineSampleSegments(samples) {
                let result = cutFractionsForSplineSegmentLineIntersection(
                    segment: segment,
                    cutter: cutter,
                    extendsCutter: extendsCutter
                )
                rejectedByCutterReach = rejectedByCutterReach || result.rejectedByCutterReach
                fractions.append(contentsOf: result.fractions)
            }
            if fractions.isEmpty && rejectedByCutterReach {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
                )
            }
            return fractions
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return cutCurveSplineSampleSegments(samples).flatMap { segment in
                cutFractionsForSplineSegmentCircleIntersection(
                    segment: segment,
                    circle: cutter,
                    restrictToArc: nil
                )
            }
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return cutCurveSplineSampleSegments(samples).flatMap { segment in
                cutFractionsForSplineSegmentCircleIntersection(
                    segment: segment,
                    circle: cutter.circle,
                    restrictToArc: extendsCutter ? nil : cutter
                )
            }
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            return cutFractionsForSplineSplineIntersection(
                targetSamples: samples,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
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

    private func validateCutSketchCurveSelections(
        targetSelection: EditableSketchEntitySelection,
        cutterSelection: EditableSketchEntitySelection,
        options: CutCurveOptions
    ) throws {
        guard options.usesScreenSpaceDirection == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve screen-space direction requires a 3D cutter context that is not represented yet."
            )
        }
        guard targetSelection.featureID != cutterSelection.featureID ||
            targetSelection.entityID != cutterSelection.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve requires distinct target and cutter curves."
            )
        }
        guard targetSelection.sketch.plane == cutterSelection.sketch.plane else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source curve cutter requires target and cutter to share a sketch plane."
            )
        }
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

    private func cutAnglesForCircleTarget(
        target: CutCurveCircle,
        cutterSelection: EditableSketchEntitySelection,
        extendsCutter: Bool
    ) throws -> [Double] {
        let angles: [Double]
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            angles = try cutAnglesForCircleCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: extendsCutter ? nil : cutter
            )
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            angles = cutAnglesForCircleSplineIntersection(
                target: target,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
        let uniqueAngles = uniqueCutAngles(angles)
        guard uniqueAngles.count == 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve circle target requires two distinct cutter intersections to create two arc segments."
            )
        }
        return uniqueAngles
    }

    private func cutFractionsForArcTarget(
        target: CutCurveArc,
        cutterSelection: (
            featureID: FeatureID,
            entityID: SketchEntityID,
            feature: FeatureNode,
            sketch: Sketch,
            entity: SketchEntity
        ),
        extendsCutter: Bool
    ) throws -> [Double] {
        switch cutterSelection.entity {
        case .line(let cutterLine):
            let cutter = try resolvedCutCurveLineSegment(cutterLine, owner: "Cut Curve cutter")
            return try cutFractionsForArcLineIntersection(
                target: target,
                cutter: cutter,
                extendsCutter: extendsCutter
            )
        case .circle(let circle):
            let cutter = try resolvedCutCurveCircle(circle, owner: "Cut Curve cutter")
            return try cutFractionsForArcCircleIntersection(
                target: target,
                circle: cutter,
                restrictToArc: nil
            )
        case .arc(let arc):
            let cutter = try resolvedCutCurveArc(arc, owner: "Cut Curve cutter")
            return try cutFractionsForArcCircleIntersection(
                target: target,
                circle: cutter.circle,
                restrictToArc: extendsCutter ? nil : cutter
            )
        case .spline(let spline):
            guard extendsCutter == false else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve spline cutter extension is not represented in the current source subset."
                )
            }
            let cutterSamples = try resolvedCutCurveSplineSamples(
                spline,
                owner: "Cut Curve cutter"
            )
            return cutFractionsForArcSplineIntersection(
                target: target,
                cutterSamples: cutterSamples
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve source subset requires a line, circle, arc, or open spline cutter curve."
            )
        }
    }

    private func resolvedCutCurveLineSegment(
        _ line: SketchLine,
        owner: String
    ) throws -> CutCurveLineSegment {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        guard hypot(deltaX, deltaY) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) length must be greater than zero."
            )
        }
        return CutCurveLineSegment(
            startX: startX,
            startY: startY,
            endX: endX,
            endY: endY
        )
    }

    private func resolvedCutCurveCircle(
        _ circle: SketchCircle,
        owner: String
    ) throws -> CutCurveCircle {
        let centerX = try resolvedLengthValue(circle.center.x, owner: "\(owner) center x")
        let centerY = try resolvedLengthValue(circle.center.y, owner: "\(owner) center y")
        let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) radius")
        return CutCurveCircle(centerX: centerX, centerY: centerY, radius: radius)
    }

    private func resolvedCutCurveArc(
        _ arc: SketchArc,
        owner: String
    ) throws -> CutCurveArc {
        let circle = try resolvedCutCurveCircle(
            SketchCircle(center: arc.center, radius: arc.radius),
            owner: owner
        )
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        return CutCurveArc(circle: circle, startAngle: startAngle, endAngle: endAngle)
    }

    private func resolvedCutCurveSplineSamples(
        _ spline: SketchSpline,
        owner: String
    ) throws -> [CurveEvaluationSample] {
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an open spline curve."
            )
        }
        let controlPoints = try spline.controlPoints.map { point in
            let resolved = try resolvedPoint(point, owner: owner)
            return Point2D(x: resolved.x, y: resolved.y)
        }
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }
        let samples = SketchCurveSampler(
            samplesPerSegment: Self.cutCurveSplineSamplesPerSegment
        )
        .splineSamples(for: controlPoints)
        guard samples.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a spline with non-zero sampled length."
            )
        }
        return samples
    }

    private func cutFractionsForLineLineIntersection(
        target: CutCurveLineSegment,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let denominator = targetX * cutterY - targetY * cutterX
        guard abs(denominator) > 1.0e-14 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve line cutter must intersect the target line; parallel or overlapping lines are unsupported."
            )
        }

        let deltaX = cutter.startX - target.startX
        let deltaY = cutter.startY - target.startY
        let targetFraction = (deltaX * cutterY - deltaY * cutterX) / denominator
        let cutterFraction = (deltaX * targetY - deltaY * targetX) / denominator
        let tolerance = 1.0e-10
        guard targetFraction > tolerance,
              targetFraction < 1.0 - tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve intersection must fall inside the target curve segment, not on its endpoint."
            )
        }
        if extendsCutter == false {
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
                )
            }
        }
        return [targetFraction]
    }

    private func cutCurveSplineSampleSegments(
        _ samples: [CurveEvaluationSample]
    ) -> [CutCurveSplineSampleSegment] {
        zip(samples, samples.dropFirst()).compactMap { start, end in
            let length = hypot(end.point.x - start.point.x, end.point.y - start.point.y)
            guard length > ModelingTolerance.standard.distance else {
                return nil
            }
            return (start: start, end: end)
        }
    }

    private func cutFractionsForLineSplineIntersection(
        target: CutCurveLineSegment,
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        cutCurveSplineSampleSegments(cutterSamples).flatMap { segment in
            cutFractionsForLineTargetSplineSegmentIntersection(
                target: target,
                cutterSegment: segment
            )
        }
    }

    private func cutFractionsForArcSplineIntersection(
        target: CutCurveArc,
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        cutCurveSplineSampleSegments(cutterSamples).flatMap { segment in
            cutFractionsForArcTargetSplineSegmentIntersection(
                target: target,
                cutterSegment: segment
            )
        }
    }

    private func cutAnglesForCircleSplineIntersection(
        target: CutCurveCircle,
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        cutCurveSplineSampleSegments(cutterSamples).flatMap { segment in
            cutAnglesForCircleTargetSplineSegmentIntersection(
                target: target,
                cutterSegment: segment
            )
        }
    }

    private func cutFractionsForSplineSplineIntersection(
        targetSamples: [CurveEvaluationSample],
        cutterSamples: [CurveEvaluationSample]
    ) -> [Double] {
        let targetSegments = cutCurveSplineSampleSegments(targetSamples)
        let cutterSegments = cutCurveSplineSampleSegments(cutterSamples)
        var fractions: [Double] = []
        for targetSegment in targetSegments {
            for cutterSegment in cutterSegments where cutCurveSampleSegmentsMayIntersect(
                targetSegment,
                cutterSegment
            ) {
                fractions.append(
                    contentsOf: cutFractionsForSplineSegmentSplineSegmentIntersection(
                        targetSegment: targetSegment,
                        cutterSegment: cutterSegment
                    )
                )
            }
        }
        return fractions
    }

    private func cutFractionsForLineTargetSplineSegmentIntersection(
        target: CutCurveLineSegment,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        guard let fractions = cutCurveLineIntersectionFractions(
            firstStartX: target.startX,
            firstStartY: target.startY,
            firstEndX: target.endX,
            firstEndY: target.endY,
            secondStartX: cutterSegment.start.point.x,
            secondStartY: cutterSegment.start.point.y,
            secondEndX: cutterSegment.end.point.x,
            secondEndY: cutterSegment.end.point.y
        ) else {
            return []
        }
        let tolerance = 1.0e-10
        guard fractions.first > tolerance,
              fractions.first < 1.0 - tolerance else {
            return []
        }
        return [fractions.first]
    }

    private func cutFractionsForArcTargetSplineSegmentIntersection(
        target: CutCurveArc,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        let cutterX = cutterSegment.end.point.x - cutterSegment.start.point.x
        let cutterY = cutterSegment.end.point.y - cutterSegment.start.point.y
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutterSegment.start.point.x - target.circle.centerX
        let offsetY = cutterSegment.start.point.y - target.circle.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.circle.radius * target.circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let cutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            cutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            cutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return cutterFractions.compactMap { cutterFraction -> Double? in
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                return nil
            }
            let pointX = cutterSegment.start.point.x + cutterX * cutterFraction
            let pointY = cutterSegment.start.point.y + cutterY * cutterFraction
            let angle = atan2(pointY - target.circle.centerY, pointX - target.circle.centerX)
            guard cutCurveAngleIsOnArc(
                angle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            return cutCurveArcFraction(for: angle, on: target)
        }
    }

    private func cutAnglesForCircleTargetSplineSegmentIntersection(
        target: CutCurveCircle,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        let cutterX = cutterSegment.end.point.x - cutterSegment.start.point.x
        let cutterY = cutterSegment.end.point.y - cutterSegment.start.point.y
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutterSegment.start.point.x - target.centerX
        let offsetY = cutterSegment.start.point.y - target.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.radius * target.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let cutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            cutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            cutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return cutterFractions.compactMap { cutterFraction -> Double? in
            guard cutterFraction >= -tolerance,
                  cutterFraction <= 1.0 + tolerance else {
                return nil
            }
            let pointX = cutterSegment.start.point.x + cutterX * cutterFraction
            let pointY = cutterSegment.start.point.y + cutterY * cutterFraction
            return atan2(pointY - target.centerY, pointX - target.centerX)
        }
    }

    private func cutFractionsForSplineSegmentSplineSegmentIntersection(
        targetSegment: CutCurveSplineSampleSegment,
        cutterSegment: CutCurveSplineSampleSegment
    ) -> [Double] {
        guard let fractions = cutCurveLineIntersectionFractions(
            firstStartX: targetSegment.start.point.x,
            firstStartY: targetSegment.start.point.y,
            firstEndX: targetSegment.end.point.x,
            firstEndY: targetSegment.end.point.y,
            secondStartX: cutterSegment.start.point.x,
            secondStartY: cutterSegment.start.point.y,
            secondEndX: cutterSegment.end.point.x,
            secondEndY: cutterSegment.end.point.y
        ) else {
            return []
        }
        return [
            cutCurveSplineSegmentParameter(
                segment: targetSegment,
                localFraction: fractions.first
            ),
        ]
    }

    private func cutCurveLineIntersectionFractions(
        firstStartX: Double,
        firstStartY: Double,
        firstEndX: Double,
        firstEndY: Double,
        secondStartX: Double,
        secondStartY: Double,
        secondEndX: Double,
        secondEndY: Double
    ) -> (first: Double, second: Double)? {
        let firstX = firstEndX - firstStartX
        let firstY = firstEndY - firstStartY
        let secondX = secondEndX - secondStartX
        let secondY = secondEndY - secondStartY
        let denominator = firstX * secondY - firstY * secondX
        guard abs(denominator) > 1.0e-14 else {
            return nil
        }

        let deltaX = secondStartX - firstStartX
        let deltaY = secondStartY - firstStartY
        let firstFraction = (deltaX * secondY - deltaY * secondX) / denominator
        let secondFraction = (deltaX * firstY - deltaY * firstX) / denominator
        let tolerance = 1.0e-10
        guard firstFraction >= -tolerance,
              firstFraction <= 1.0 + tolerance,
              secondFraction >= -tolerance,
              secondFraction <= 1.0 + tolerance else {
            return nil
        }
        return (
            first: min(max(firstFraction, 0.0), 1.0),
            second: min(max(secondFraction, 0.0), 1.0)
        )
    }

    private func cutCurveSampleSegmentsMayIntersect(
        _ first: CutCurveSplineSampleSegment,
        _ second: CutCurveSplineSampleSegment
    ) -> Bool {
        let tolerance = 1.0e-10
        let firstMinX = min(first.start.point.x, first.end.point.x) - tolerance
        let firstMaxX = max(first.start.point.x, first.end.point.x) + tolerance
        let firstMinY = min(first.start.point.y, first.end.point.y) - tolerance
        let firstMaxY = max(first.start.point.y, first.end.point.y) + tolerance
        let secondMinX = min(second.start.point.x, second.end.point.x) - tolerance
        let secondMaxX = max(second.start.point.x, second.end.point.x) + tolerance
        let secondMinY = min(second.start.point.y, second.end.point.y) - tolerance
        let secondMaxY = max(second.start.point.y, second.end.point.y) + tolerance
        return firstMaxX >= secondMinX &&
            secondMaxX >= firstMinX &&
            firstMaxY >= secondMinY &&
            secondMaxY >= firstMinY
    }

    private func cutFractionsForSplineSegmentLineIntersection(
        segment: CutCurveSplineSampleSegment,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) -> (fractions: [Double], rejectedByCutterReach: Bool) {
        let targetX = segment.end.point.x - segment.start.point.x
        let targetY = segment.end.point.y - segment.start.point.y
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let denominator = targetX * cutterY - targetY * cutterX
        guard abs(denominator) > 1.0e-14 else {
            return (fractions: [], rejectedByCutterReach: false)
        }

        let deltaX = cutter.startX - segment.start.point.x
        let deltaY = cutter.startY - segment.start.point.y
        let targetFraction = (deltaX * cutterY - deltaY * cutterX) / denominator
        let cutterFraction = (deltaX * targetY - deltaY * targetX) / denominator
        let tolerance = 1.0e-10
        guard targetFraction >= -tolerance,
              targetFraction <= 1.0 + tolerance else {
            return (fractions: [], rejectedByCutterReach: false)
        }
        if extendsCutter == false &&
            (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
            return (fractions: [], rejectedByCutterReach: true)
        }
        return (
            fractions: [
                cutCurveSplineSegmentParameter(
                    segment: segment,
                    localFraction: targetFraction
                ),
            ],
            rejectedByCutterReach: false
        )
    }

    private func cutFractionsForSplineSegmentCircleIntersection(
        segment: CutCurveSplineSampleSegment,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) -> [Double] {
        let targetX = segment.end.point.x - segment.start.point.x
        let targetY = segment.end.point.y - segment.start.point.y
        let lengthSquared = targetX * targetX + targetY * targetY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = segment.start.point.x - circle.centerX
        let offsetY = segment.start.point.y - circle.centerY
        let b = 2.0 * (offsetX * targetX + offsetY * targetY)
        let c = offsetX * offsetX + offsetY * offsetY - circle.radius * circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }

        let root = sqrt(max(discriminant, 0.0))
        let localFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            localFractions = [-b / (2.0 * lengthSquared)]
        } else {
            localFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return localFractions.compactMap { localFraction -> Double? in
            guard localFraction >= -tolerance,
                  localFraction <= 1.0 + tolerance else {
                return nil
            }
            let pointX = segment.start.point.x + targetX * localFraction
            let pointY = segment.start.point.y + targetY * localFraction
            if let arc {
                let angle = atan2(pointY - arc.circle.centerY, pointX - arc.circle.centerX)
                guard cutCurveAngleIsOnArc(
                    angle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return cutCurveSplineSegmentParameter(
                segment: segment,
                localFraction: localFraction
            )
        }
    }

    private func cutCurveSplineSegmentParameter(
        segment: CutCurveSplineSampleSegment,
        localFraction: Double
    ) -> Double {
        let clampedFraction = min(max(localFraction, 0.0), 1.0)
        return segment.start.parameter +
            (segment.end.parameter - segment.start.parameter) * clampedFraction
    }

    private func cutFractionsForLineCircleIntersection(
        target: CutCurveLineSegment,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) -> [Double] {
        let targetX = target.endX - target.startX
        let targetY = target.endY - target.startY
        let lengthSquared = targetX * targetX + targetY * targetY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = target.startX - circle.centerX
        let offsetY = target.startY - circle.centerY
        let b = 2.0 * (offsetX * targetX + offsetY * targetY)
        let c = offsetX * offsetX + offsetY * offsetY - circle.radius * circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        return rawFractions.filter { fraction in
            guard fraction > tolerance,
                  fraction < 1.0 - tolerance else {
                return false
            }
            guard let arc else {
                return true
            }
            let pointX = target.startX + targetX * fraction
            let pointY = target.startY + targetY * fraction
            let angle = atan2(pointY - arc.circle.centerY, pointX - arc.circle.centerX)
            return cutCurveAngleIsOnArc(angle, startAngle: arc.startAngle, endAngle: arc.endAngle)
        }
    }

    private func cutFractionsForArcLineIntersection(
        target: CutCurveArc,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.circle.centerX
        let offsetY = cutter.startY - target.circle.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.circle.radius * target.circle.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let targetFractions = rawCutterFractions.compactMap { cutterFraction -> Double? in
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            let angle = atan2(pointY - target.circle.centerY, pointX - target.circle.centerX)
            guard cutCurveAngleIsOnArc(
                angle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            return cutCurveArcFraction(for: angle, on: target)
        }
        if targetFractions.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return targetFractions
    }

    private func cutFractionsForArcCircleIntersection(
        target: CutCurveArc,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target.circle,
            circle
        )
        return points.compactMap { point -> Double? in
            let targetAngle = atan2(
                point.y - target.circle.centerY,
                point.x - target.circle.centerX
            )
            guard cutCurveAngleIsOnArc(
                targetAngle,
                startAngle: target.startAngle,
                endAngle: target.endAngle
            ) else {
                return nil
            }
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return cutCurveArcFraction(for: targetAngle, on: target)
        }
    }

    private func cutAnglesForCircleLineIntersection(
        target: CutCurveCircle,
        cutter: CutCurveLineSegment,
        extendsCutter: Bool
    ) throws -> [Double] {
        let cutterX = cutter.endX - cutter.startX
        let cutterY = cutter.endY - cutter.startY
        let lengthSquared = cutterX * cutterX + cutterY * cutterY
        guard lengthSquared > 1.0e-24 else {
            return []
        }
        let offsetX = cutter.startX - target.centerX
        let offsetY = cutter.startY - target.centerY
        let b = 2.0 * (offsetX * cutterX + offsetY * cutterY)
        let c = offsetX * offsetX + offsetY * offsetY - target.radius * target.radius
        let discriminant = b * b - 4.0 * lengthSquared * c
        guard discriminant >= -1.0e-14 else {
            return []
        }
        let root = sqrt(max(discriminant, 0.0))
        let rawCutterFractions: [Double]
        if abs(discriminant) <= 1.0e-14 {
            rawCutterFractions = [-b / (2.0 * lengthSquared)]
        } else {
            rawCutterFractions = [
                (-b - root) / (2.0 * lengthSquared),
                (-b + root) / (2.0 * lengthSquared),
            ]
        }
        let tolerance = 1.0e-10
        var rejectedByCutterReach = false
        let angles = rawCutterFractions.compactMap { cutterFraction -> Double? in
            if extendsCutter == false &&
                (cutterFraction < -tolerance || cutterFraction > 1.0 + tolerance) {
                rejectedByCutterReach = true
                return nil
            }
            let pointX = cutter.startX + cutterX * cutterFraction
            let pointY = cutter.startY + cutterY * cutterFraction
            return atan2(pointY - target.centerY, pointX - target.centerX)
        }
        if angles.isEmpty && rejectedByCutterReach {
            throw EditorError(
                code: .commandInvalid,
                message: "Cut Curve cutter does not reach the target curve; enable cutter extension for this case."
            )
        }
        return angles
    }

    private func cutAnglesForCircleCircleIntersection(
        target: CutCurveCircle,
        circle: CutCurveCircle,
        restrictToArc arc: CutCurveArc?
    ) throws -> [Double] {
        let points = try cutCurveCircleCircleIntersections(
            target,
            circle
        )
        return points.compactMap { point -> Double? in
            if let arc {
                let cutterAngle = atan2(
                    point.y - arc.circle.centerY,
                    point.x - arc.circle.centerX
                )
                guard cutCurveAngleIsOnArc(
                    cutterAngle,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle
                ) else {
                    return nil
                }
            }
            return atan2(point.y - target.centerY, point.x - target.centerX)
        }
    }

    private func cutCurveCircleCircleIntersections(
        _ first: CutCurveCircle,
        _ second: CutCurveCircle
    ) throws -> [(x: Double, y: Double)] {
        let deltaX = second.centerX - first.centerX
        let deltaY = second.centerY - first.centerY
        let distance = hypot(deltaX, deltaY)
        let tolerance = 1.0e-10
        guard distance > tolerance else {
            if abs(first.radius - second.radius) <= tolerance {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Cut Curve coincident circular curves do not create discrete intersections in the current source subset."
                )
            }
            return []
        }
        guard distance <= first.radius + second.radius + tolerance,
              distance >= abs(first.radius - second.radius) - tolerance else {
            return []
        }

        let firstRadiusSquared = first.radius * first.radius
        let secondRadiusSquared = second.radius * second.radius
        let distanceSquared = distance * distance
        let centerOffset = (firstRadiusSquared - secondRadiusSquared + distanceSquared) /
            (2.0 * distance)
        let heightSquared = firstRadiusSquared - centerOffset * centerOffset
        guard heightSquared >= -1.0e-14 else {
            return []
        }

        let unitX = deltaX / distance
        let unitY = deltaY / distance
        let baseX = first.centerX + centerOffset * unitX
        let baseY = first.centerY + centerOffset * unitY
        let height = sqrt(max(heightSquared, 0.0))
        if height <= tolerance {
            return [(x: baseX, y: baseY)]
        }
        let perpendicularX = -unitY * height
        let perpendicularY = unitX * height
        return [
            (x: baseX + perpendicularX, y: baseY + perpendicularY),
            (x: baseX - perpendicularX, y: baseY - perpendicularY),
        ]
    }

    private func uniqueInteriorCutFractions(_ fractions: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        return fractions
            .filter { fraction in
                fraction > tolerance && fraction < 1.0 - tolerance
            }
            .sorted()
            .reduce(into: [Double]()) { uniqueFractions, fraction in
                guard uniqueFractions.contains(where: { abs($0 - fraction) <= tolerance }) == false else {
                    return
                }
                uniqueFractions.append(fraction)
            }
    }

    private func uniqueCutAngles(_ angles: [Double]) -> [Double] {
        let tolerance = 1.0e-10
        let fullCircle = Double.pi * 2.0
        var uniqueAngles = angles
            .map(normalizedCutAngle)
            .sorted()
            .reduce(into: [Double]()) { uniqueAngles, angle in
                guard uniqueAngles.contains(where: { abs($0 - angle) <= tolerance }) == false else {
                    return
                }
                uniqueAngles.append(angle)
            }
        if let first = uniqueAngles.first,
           let last = uniqueAngles.last,
           uniqueAngles.count > 1,
           fullCircle - last + first <= tolerance {
            uniqueAngles.removeLast()
        }
        return uniqueAngles
    }

    private func normalizedCutAngle(_ angle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        var normalized = angle
        while normalized < 0.0 {
            normalized += fullCircle
        }
        while normalized >= fullCircle {
            normalized -= fullCircle
        }
        if fullCircle - normalized <= 1.0e-10 {
            return 0.0
        }
        return normalized
    }

    private func cutCurveAngleIsOnArc(
        _ angle: Double,
        startAngle: Double,
        endAngle: Double
    ) -> Bool {
        normalizedAngleDelta(from: startAngle, to: angle) <=
            positiveArcSpan(startAngle: startAngle, endAngle: endAngle) + 1.0e-10
    }

    private func cutCurveArcFraction(
        for angle: Double,
        on arc: CutCurveArc
    ) -> Double {
        normalizedAngleDelta(from: arc.startAngle, to: angle) /
            positiveArcSpan(startAngle: arc.startAngle, endAngle: arc.endAngle)
    }

    private func normalizedAngleDelta(
        from startAngle: Double,
        to angle: Double
    ) -> Double {
        let fullCircle = Double.pi * 2.0
        var delta = angle - startAngle
        while delta < 0.0 {
            delta += fullCircle
        }
        while delta >= fullCircle {
            delta -= fullCircle
        }
        return delta
    }

    private func splitSketchCurveEntity(
        _ entity: SketchEntity,
        entityID: SketchEntityID,
        newEntityID: SketchEntityID,
        fraction: Double,
        owner: String
    ) throws -> SketchCurveSegmentSplitResult {
        switch entity {
        case .line(let line):
            let splitPoint = try splitPoint(on: line, fraction: fraction, owner: owner)
            let retainedLine = SketchLine(start: line.start, end: splitPoint)
            let newLine = SketchLine(start: splitPoint, end: line.end)
            _ = try resolvedLineMetrics(retainedLine, owner: owner)
            _ = try resolvedLineMetrics(newLine, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .line(retainedLine),
                newEntity: .line(newLine),
                insertedRetainedReference: .lineEnd(entityID),
                insertedNewReference: .lineStart(newEntityID),
                originalEndReference: .lineEnd(entityID),
                migratedEndReference: .lineEnd(newEntityID)
            )
        case .spline(let spline):
            let split = try splitSpline(
                spline,
                fraction: fraction,
                owner: owner
            )
            try validateSpline(split.retained, owner: owner)
            try validateSpline(split.new, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .spline(split.retained),
                newEntity: .spline(split.new),
                insertedRetainedReference: .splineControlPoint(
                    entity: entityID,
                    index: split.retained.controlPoints.count - 1
                ),
                insertedNewReference: .splineControlPoint(entity: newEntityID, index: 0),
                originalEndReference: .splineControlPoint(
                    entity: entityID,
                    index: spline.controlPoints.count - 1
                ),
                migratedEndReference: .splineControlPoint(
                    entity: newEntityID,
                    index: split.new.controlPoints.count - 1
                )
            )
        case .arc(let arc):
            let split = try splitArc(
                arc,
                fraction: fraction,
                owner: owner
            )
            try validateArc(split.retained, owner: owner)
            try validateArc(split.new, owner: owner)
            return SketchCurveSegmentSplitResult(
                originalEntityID: entityID,
                newEntityID: newEntityID,
                fraction: fraction,
                retainedEntity: .arc(split.retained),
                newEntity: .arc(split.new),
                insertedRetainedReference: .arcEnd(entityID),
                insertedNewReference: .arcStart(newEntityID),
                originalEndReference: .arcEnd(entityID),
                migratedEndReference: .arcEnd(newEntityID)
            )
        case .point,
             .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line, arc, or spline curve target."
            )
        }
    }

    func splitArc(
        _ arc: SketchArc,
        fraction: Double,
        owner: String
    ) throws -> (retained: SketchArc, new: SketchArc) {
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
        let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let splitAngle = startAngle + span * fraction
        let splitExpression = CADExpression.angle(splitAngle, .radian)
        return (
            retained: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: arc.startAngle,
                endAngle: splitExpression
            ),
            new: SketchArc(
                center: arc.center,
                radius: arc.radius,
                startAngle: splitExpression,
                endAngle: arc.endAngle
            )
        )
    }

    func splitPoint(
        on line: SketchLine,
        fraction: Double,
        owner: String
    ) throws -> SketchPoint {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) end y")
        let deltaX = endX - startX
        let deltaY = endY - startY
        guard hypot(deltaX, deltaY) > ModelingTolerance.standard.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        return sketchPoint(
            x: startX + deltaX * fraction,
            y: startY + deltaY * fraction
        )
    }

    func splitSpline(
        _ spline: SketchSpline,
        fraction: Double,
        owner: String
    ) throws -> (retained: SketchSpline, new: SketchSpline) {
        let controlPoints = spline.controlPoints
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a cubic Bezier spline."
            )
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let scaledParameter = fraction * Double(segmentCount)
        var segmentIndex = Int(floor(scaledParameter))
        let localFraction = scaledParameter - Double(segmentIndex)
        let tolerance = 1.0e-9

        if localFraction <= tolerance {
            guard segmentIndex > 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) fraction must not resolve to the spline start."
                )
            }
            return splitSplineAtExistingKnot(
                spline,
                knotIndex: segmentIndex * 3,
                owner: owner
            )
        }
        if localFraction >= 1.0 - tolerance {
            segmentIndex += 1
            guard segmentIndex < segmentCount else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) fraction must not resolve to the spline end."
                )
            }
            return splitSplineAtExistingKnot(
                spline,
                knotIndex: segmentIndex * 3,
                owner: owner
            )
        }

        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let split = splitCubicBezier(
            p0,
            p1,
            p2,
            p3,
            fraction: .scalar(localFraction)
        )
        var retained = Array(controlPoints[0 ... segmentStart])
        retained.append(contentsOf: [split.left.1, split.left.2, split.left.3])
        var next = [split.right.0, split.right.1, split.right.2, split.right.3]
        if segmentStart + 4 < controlPoints.count {
            next.append(contentsOf: controlPoints[(segmentStart + 4)...])
        }
        guard retained.count >= 4,
              next.count >= 4 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced an invalid spline split."
            )
        }
        return (
            retained: SketchSpline(controlPoints: retained),
            new: SketchSpline(controlPoints: next)
        )
    }

    private func splitSplineAtExistingKnot(
        _ spline: SketchSpline,
        knotIndex: Int,
        owner: String
    ) -> (retained: SketchSpline, new: SketchSpline) {
        let controlPoints = spline.controlPoints
        precondition(knotIndex > 0 && knotIndex < controlPoints.count - 1)
        let retained = Array(controlPoints[0 ... knotIndex])
        let next = Array(controlPoints[knotIndex...])
        return (
            retained: SketchSpline(controlPoints: retained),
            new: SketchSpline(controlPoints: next)
        )
    }

    func splitCubicBezier(
        _ p0: SketchPoint,
        _ p1: SketchPoint,
        _ p2: SketchPoint,
        _ p3: SketchPoint,
        fraction: CADExpression
    ) -> (
        left: (SketchPoint, SketchPoint, SketchPoint, SketchPoint),
        right: (SketchPoint, SketchPoint, SketchPoint, SketchPoint)
    ) {
        let q0 = interpolatedSketchPoint(p0, p1, fraction: fraction)
        let q1 = interpolatedSketchPoint(p1, p2, fraction: fraction)
        let q2 = interpolatedSketchPoint(p2, p3, fraction: fraction)
        let r0 = interpolatedSketchPoint(q0, q1, fraction: fraction)
        let r1 = interpolatedSketchPoint(q1, q2, fraction: fraction)
        let s = interpolatedSketchPoint(r0, r1, fraction: fraction)
        return (
            left: (p0, q0, r0, s),
            right: (s, r1, q2, p3)
        )
    }

    private func interpolatedSketchPoint(
        _ first: SketchPoint,
        _ second: SketchPoint,
        fraction: CADExpression
    ) -> SketchPoint {
        SketchPoint(
            x: .add(first.x, .multiply(.subtract(second.x, first.x), fraction)),
            y: .add(first.y, .multiply(.subtract(second.y, first.y), fraction))
        )
    }

    private func constraintsAfterSketchCurveSplit(
        _ constraints: [SketchConstraint],
        split: SketchCurveSegmentSplitResult
    ) -> [SketchConstraint] {
        var updated: [SketchConstraint] = []
        for constraint in constraints {
            switch constraint {
            case .coincident(let first, let second):
                updated.append(.coincident(
                    rewriteSketchReferenceAfterCurveSplit(first, split: split),
                    rewriteSketchReferenceAfterCurveSplit(second, split: split)
                ))
            case .fixed(let reference):
                updated.append(.fixed(rewriteSketchReferenceAfterCurveSplit(reference, split: split)))
            case .horizontal(let entityID):
                updated.append(constraint)
                if entityID == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.horizontal(split.newEntityID))
                }
            case .vertical(let entityID):
                updated.append(constraint)
                if entityID == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.vertical(split.newEntityID))
                }
            case .parallel(let first, let second):
                updated.append(constraint)
                if first == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.parallel(split.newEntityID, second))
                } else if second == split.originalEntityID,
                          case .line = split.retainedEntity {
                    updated.append(.parallel(first, split.newEntityID))
                }
            case .perpendicular(let first, let second):
                updated.append(constraint)
                if first == split.originalEntityID,
                   case .line = split.retainedEntity {
                    updated.append(.perpendicular(split.newEntityID, second))
                } else if second == split.originalEntityID,
                          case .line = split.retainedEntity {
                    updated.append(.perpendicular(first, split.newEntityID))
                }
            case .splineEndpointTangent(let splineID, let endpoint, let lineID):
                if splineID == split.originalEntityID,
                   endpoint == .end {
                    updated.append(.splineEndpointTangent(
                        spline: split.newEntityID,
                        endpoint: .end,
                        line: lineID
                    ))
                } else {
                    updated.append(constraint)
                }
            case .tangentSplineEndpoints(let first, let second):
                updated.append(.tangentSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveSplit(first, split: split),
                    second: rewriteSplineEndpointReferenceAfterCurveSplit(second, split: split)
                ))
            case .smoothSplineEndpoints(let first, let second):
                updated.append(.smoothSplineEndpoints(
                    first: rewriteSplineEndpointReferenceAfterCurveSplit(first, split: split),
                    second: rewriteSplineEndpointReferenceAfterCurveSplit(second, split: split)
                ))
            case .equalLength,
                 .tangent,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint:
                updated.append(constraint)
            }
        }
        updated.append(.coincident(split.insertedRetainedReference, split.insertedNewReference))
        return updated
    }

    private func dimensionsAfterSketchCurveSplit(
        _ dimensions: [SketchDimension],
        split: SketchCurveSegmentSplitResult
    ) -> [SketchDimension] {
        dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value):
                return .distance(
                    from: rewriteSketchReferenceAfterCurveSplit(from, split: split),
                    to: rewriteSketchReferenceAfterCurveSplit(to, split: split),
                    value: value
                )
            case .angle(let from, let to, let value):
                return .angle(
                    from: rewriteSketchReferenceAfterCurveSplit(from, split: split),
                    to: rewriteSketchReferenceAfterCurveSplit(to, split: split),
                    value: value
                )
            case .radius, .diameter:
                return dimension
            }
        }
    }

    private func bridgeCurveSourcesAfterSketchCurveSplit(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        split: SketchCurveSegmentSplitResult
    ) throws -> [BridgeCurveSourceID: BridgeCurveSource] {
        try sources.mapValues { source in
            BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: try rewriteBridgeEndpointAfterCurveSplit(source.firstEndpoint, split: split),
                secondEndpoint: try rewriteBridgeEndpointAfterCurveSplit(source.secondEndpoint, split: split),
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
    }

    private func rewriteBridgeEndpointAfterCurveSplit(
        _ endpoint: BridgeCurveEndpoint,
        split: SketchCurveSegmentSplitResult
    ) throws -> BridgeCurveEndpoint {
        guard let parameter = endpoint.parameter,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: split.originalEntityID) else {
            return BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveSplit(endpoint.reference, split: split),
                parameter: endpoint.parameter,
                reversesSense: endpoint.reversesSense,
                tension: endpoint.tension
            )
        }

        let resolvedParameter = try resolvedScalarValue(
            parameter,
            owner: "Bridge curve endpoint parameter"
        )
        let splitExpression = CADExpression.scalar(split.fraction)
        if resolvedParameter <= split.fraction {
            return BridgeCurveEndpoint(
                reference: endpoint.reference,
                parameter: .divide(parameter, splitExpression),
                reversesSense: endpoint.reversesSense,
                tension: endpoint.tension
            )
        }
        return BridgeCurveEndpoint(
            reference: rewriteBridgeParametricReferenceToNewSplitEntity(
                endpoint.reference,
                split: split
            ),
            parameter: .divide(
                .subtract(parameter, splitExpression),
                .subtract(.scalar(1.0), splitExpression)
            ),
            reversesSense: endpoint.reversesSense,
            tension: endpoint.tension
        )
    }

    private func rewriteBridgeParametricReferenceToNewSplitEntity(
        _ reference: SketchReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchReference {
        switch reference {
        case .entity(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .lineStart(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .lineEnd(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .arcStart(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .arcEnd(let entityID) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        case .splineControlPoint(let entityID, _) where entityID == split.originalEntityID:
            return .entity(split.newEntityID)
        default:
            return reference
        }
    }

    private func rewriteSketchReferenceAfterCurveSplit(
        _ reference: SketchReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchReference {
        reference == split.originalEndReference ? split.migratedEndReference : reference
    }

    private func rewriteSplineEndpointReferenceAfterCurveSplit(
        _ reference: SketchSplineEndpointReference,
        split: SketchCurveSegmentSplitResult
    ) -> SketchSplineEndpointReference {
        guard reference.splineID == split.originalEntityID,
              reference.endpoint == .end else {
            return reference
        }
        return SketchSplineEndpointReference(splineID: split.newEntityID, endpoint: .end)
    }

    private func bridgeCurveSourcesAfterSketchCurveReverse(
        _ sources: [BridgeCurveSourceID: BridgeCurveSource],
        featureID: FeatureID,
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> [BridgeCurveSourceID: BridgeCurveSource] {
        sources.mapValues { source in
            let firstEndpoint = BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveReverse(
                    source.firstEndpoint.reference,
                    entityID: entityID,
                    splineControlPointCount: splineControlPointCount
                ),
                parameter: rewriteBridgeEndpointParameterAfterCurveReverse(
                    source.firstEndpoint,
                    entityID: entityID
                ),
                reversesSense: rewriteBridgeEndpointSenseAfterCurveReverse(
                    source.firstEndpoint,
                    entityID: entityID
                ),
                tension: source.firstEndpoint.tension
            )
            let secondEndpoint = BridgeCurveEndpoint(
                reference: rewriteSketchReferenceAfterCurveReverse(
                    source.secondEndpoint.reference,
                    entityID: entityID,
                    splineControlPointCount: splineControlPointCount
                ),
                parameter: rewriteBridgeEndpointParameterAfterCurveReverse(
                    source.secondEndpoint,
                    entityID: entityID
                ),
                reversesSense: rewriteBridgeEndpointSenseAfterCurveReverse(
                    source.secondEndpoint,
                    entityID: entityID
                ),
                tension: source.secondEndpoint.tension
            )
            if source.featureID == featureID && source.entityID == entityID {
                return BridgeCurveSource(
                    id: source.id,
                    featureID: source.featureID,
                    entityID: source.entityID,
                    firstEndpoint: secondEndpoint,
                    secondEndpoint: firstEndpoint,
                    continuity: source.continuity,
                    trimsSourceCurves: source.trimsSourceCurves
                )
            }
            return BridgeCurveSource(
                id: source.id,
                featureID: source.featureID,
                entityID: source.entityID,
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint,
                continuity: source.continuity,
                trimsSourceCurves: source.trimsSourceCurves
            )
        }
    }

    private func rewriteSketchReferenceAfterCurveReverse(
        _ reference: SketchReference,
        entityID: SketchEntityID,
        splineControlPointCount: Int?
    ) -> SketchReference {
        switch reference {
        case .lineStart(let id) where id == entityID:
            return .lineEnd(entityID)
        case .lineEnd(let id) where id == entityID:
            return .lineStart(entityID)
        case .splineControlPoint(let id, let index) where id == entityID:
            guard let count = splineControlPointCount else {
                return reference
            }
            return .splineControlPoint(
                entity: entityID,
                index: reversedSplineControlPointIndex(index, controlPointCount: count)
            )
        default:
            return reference
        }
    }

    private func rewriteBridgeEndpointParameterAfterCurveReverse(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> CADExpression? {
        guard let parameter = endpoint.parameter,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID) else {
            return endpoint.parameter
        }
        return .subtract(.scalar(1.0), parameter)
    }

    private func rewriteBridgeEndpointSenseAfterCurveReverse(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> Bool {
        guard endpoint.parameter != nil,
              bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID) else {
            return endpoint.reversesSense
        }
        return !endpoint.reversesSense
    }

    private func rewriteSplineEndpointReferenceAfterCurveReverse(
        _ reference: SketchSplineEndpointReference,
        entityID: SketchEntityID
    ) -> SketchSplineEndpointReference {
        guard reference.splineID == entityID else {
            return reference
        }
        return SketchSplineEndpointReference(
            splineID: reference.splineID,
            endpoint: reversedSplineEndpoint(reference.endpoint)
        )
    }

    private func reversedSplineEndpoint(_ endpoint: SketchSplineEndpoint) -> SketchSplineEndpoint {
        switch endpoint {
        case .start:
            return .end
        case .end:
            return .start
        }
    }

    private func reversedSplineControlPointIndex(
        _ index: Int,
        controlPointCount: Int
    ) -> Int {
        controlPointCount - 1 - index
    }

    func squaredDistance(
        _ first: (x: Double, y: Double),
        _ second: (x: Double, y: Double)
    ) -> Double {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }

    func sketchReference(
        _ reference: SketchReference,
        references entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case .entity(let id),
             .lineStart(let id),
             .lineEnd(let id),
             .circleCenter(let id),
             .circleRadius(let id),
             .arcCenter(let id),
             .arcStart(let id),
             .arcEnd(let id),
             .arcRadius(let id),
             .splineControlPoint(let id, _):
            return id == entityID
        }
    }

    func validateArc(
        _ arc: SketchArc,
        owner: String
    ) throws {
        _ = try resolvedLengthValue(arc.center.x, owner: "\(owner) center x")
        _ = try resolvedLengthValue(arc.center.y, owner: "\(owner) center y")
        _ = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
        let resolvedStartAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
        let resolvedEndAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
        _ = try normalizedPartialArcSpan(
            startAngle: resolvedStartAngle,
            endAngle: resolvedEndAngle
        )
    }

    func validateSpline(
        _ spline: SketchSpline,
        owner: String
    ) throws {
        let count = spline.controlPoints.count
        guard count >= 4, (count - 1).isMultiple(of: 3) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) control point count must be 3n + 1 and at least 4."
            )
        }
        let resolvedPoints = try spline.controlPoints.enumerated().map { index, point in
            (
                x: try resolvedLengthValue(point.x, owner: "\(owner) control point \(index) x"),
                y: try resolvedLengthValue(point.y, owner: "\(owner) control point \(index) y")
            )
        }
        for segmentIndex in stride(from: 0, to: resolvedPoints.count - 1, by: 3) {
            let start = resolvedPoints[segmentIndex]
            let end = resolvedPoints[segmentIndex + 3]
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            guard sqrt(deltaX * deltaX + deltaY * deltaY) > ModelingTolerance.standard.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) cubic segment \(segmentIndex / 3) must not collapse to a point."
                )
            }
        }
    }

    mutating func commitSketchEntityEdit(
        featureID: FeatureID,
        feature: inout FeatureNode,
        sketch: Sketch,
        objectRegistry: ObjectTypeRegistry,
        errorOwner: String
    ) throws {
        feature.operation = .sketch(sketch)
        var updatedCADDocument = cadDocument
        do {
            try updatedCADDocument.replaceFeature(feature)
        } catch {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(errorOwner) produced invalid sketch geometry: \(error)."
            )
        }

        cadDocument = updatedCADDocument
        try synchronizeSketchObjectProperties(
            featureID: featureID,
            sketch: sketch,
            objectRegistry: objectRegistry
        )
        try synchronizeObjectPropertiesAffectedBySketch(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

    mutating func synchronizeSketchObjectProperties(
        featureID: FeatureID,
        sketch: Sketch,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard sketch.entities.count == 1,
              let entity = sketch.entities.values.first else {
            return
        }
        switch entity {
        case .line(let line):
            let metrics = try resolvedLineMetrics(line, owner: "Sketch line")
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .line else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "length"),
                    to: metrics.length,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "angle"),
                    to: metrics.angleDegrees,
                    object: &object,
                    definition: definition
                )
            }
        case .circle(let circle):
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "Sketch circle radius")
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .circle else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "radius"),
                    to: radius,
                    object: &object,
                    definition: definition
                )
            }
        case .arc(let arc):
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "Sketch arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "Sketch arc start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "Sketch arc end angle")
            let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .arc else {
                    return
                }
                Self.setLengthProperty(
                    ObjectPropertyID(rawValue: "radius"),
                    to: radius,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "start.angle"),
                    to: startAngle * 180.0 / .pi,
                    object: &object,
                    definition: definition
                )
                Self.setAngleProperty(
                    ObjectPropertyID(rawValue: "end.angle"),
                    to: (startAngle + span) * 180.0 / .pi,
                    object: &object,
                    definition: definition
                )
            }
        case .spline(let spline):
            try updateSketchObjectProperties(featureID: featureID, objectRegistry: objectRegistry) { object, definition in
                guard object.typeID == .spline else {
                    return
                }
                Self.setIntegerProperty(
                    ObjectPropertyID(rawValue: "control.point.count"),
                    to: spline.controlPoints.count,
                    object: &object,
                    definition: definition
                )
            }
        case .point:
            return
        }
    }

    private mutating func updateSketchObjectProperties(
        featureID: FeatureID,
        objectRegistry: ObjectTypeRegistry,
        update: (inout ObjectDescriptor, ObjectTypeDefinition) -> Void
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch,
            object.typeID != nil else {
            return
        }
        let definition = try objectRegistry.requireDefinition(for: object.typeID)
        var resolved = definition.resolvedProperties(object.properties)
        object.properties = resolved
        update(&object, definition)
        resolved = definition.resolvedProperties(object.properties)
        try resolved.validate(
            against: definition,
            materialLibrary: productMetadata.materialLibrary
        )
        object.properties = resolved
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    mutating func setSketchObjectType(
        featureID: FeatureID,
        typeID: ObjectTypeID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch else {
            return
        }

        let definition = try objectRegistry.requireDefinition(for: typeID)
        var nextProperties = objectRegistry.defaultProperties(for: typeID)
        if let strokeWidth = object.properties[ObjectPropertyID(rawValue: "stroke.width")] {
            nextProperties[ObjectPropertyID(rawValue: "stroke.width")] = strokeWidth
        }
        nextProperties = definition.resolvedProperties(nextProperties)
        try nextProperties.validate(
            against: definition,
            materialLibrary: productMetadata.materialLibrary
        )
        object.typeID = typeID
        object.geometryRole = definition.geometryRole
        object.properties = nextProperties
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    mutating func markSketchObjectAsSourceEdited(featureID: FeatureID) throws {
        guard let nodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.object?.sourceFeatureID == featureID || node.reference?.featureID == featureID
        })?.key,
            var node = productMetadata.sceneNodes[nodeID],
            var object = node.object,
            object.category == .sketch else {
            return
        }
        object.typeID = nil
        object.properties = ObjectPropertySet()
        try object.validate()
        node.object = object
        productMetadata.sceneNodes[nodeID] = node
    }

    func normalizedPartialArcSpan(
        startAngle: Double,
        endAngle: Double
    ) throws -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= ModelingTolerance.standard.angle {
            span += fullCircle
        }
        while span > fullCircle + ModelingTolerance.standard.angle {
            span -= fullCircle
        }
        guard span > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch angle span must be greater than zero."
            )
        }
        guard span < fullCircle - ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Arc sketch must be partial; use a circle sketch for full circles."
            )
        }
        return span
    }

    private func rectangleSketch(
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) -> Sketch {
        let bottom = SketchEntityID()
        let right = SketchEntityID()
        let top = SketchEntityID()
        let left = SketchEntityID()
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        return Sketch(
            plane: plane,
            entities: [
                bottom: .line(SketchLine(start: bottomLeft, end: bottomRight)),
                right: .line(SketchLine(start: bottomRight, end: topRight)),
                top: .line(SketchLine(start: topRight, end: topLeft)),
                left: .line(SketchLine(start: topLeft, end: bottomLeft)),
            ],
            constraints: [
                .horizontal(bottom),
                .vertical(right),
                .horizontal(top),
                .vertical(left),
                .coincident(.lineEnd(bottom), .lineStart(right)),
                .coincident(.lineEnd(right), .lineStart(top)),
                .coincident(.lineEnd(top), .lineStart(left)),
                .coincident(.lineEnd(left), .lineStart(bottom)),
            ]
        )
    }

    func sketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x, .meter),
            y: .length(y, .meter)
        )
    }

    func sketchCoordinate(
        from point: TopologySummaryResult.Entry.Point,
        on plane: SketchPlane
    ) throws -> (x: Double, y: Double, depth: Double) {
        switch plane {
        case .xy:
            return (x: point.x, y: point.y, depth: point.z)
        case .yz:
            return (x: point.y, y: point.z, depth: point.x)
        case .zx:
            return (x: point.z, y: point.x, depth: point.y)
        case .plane(let plane):
            let normal = try plane.normal.normalized(tolerance: 1.0e-12)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: 1.0e-12)
            let v = normal.cross(u)
            let delta = Point3D(x: point.x, y: point.y, z: point.z) - plane.origin
            return (
                x: delta.dot(u),
                y: delta.dot(v),
                depth: delta.dot(normal)
            )
        }
    }

    func updateRectangleSketch(
        _ sketch: inout Sketch,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint
    ) throws {
        guard let lineIDs = try rectangleLineIDs(in: sketch) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Cube dimensions require an axis-aligned rectangle profile."
            )
        }
        let bottomLeft = firstCorner
        let bottomRight = SketchPoint(x: oppositeCorner.x, y: firstCorner.y)
        let topRight = oppositeCorner
        let topLeft = SketchPoint(x: firstCorner.x, y: oppositeCorner.y)
        sketch.entities[lineIDs.bottom] = .line(SketchLine(start: bottomLeft, end: bottomRight))
        sketch.entities[lineIDs.right] = .line(SketchLine(start: bottomRight, end: topRight))
        sketch.entities[lineIDs.top] = .line(SketchLine(start: topRight, end: topLeft))
        sketch.entities[lineIDs.left] = .line(SketchLine(start: topLeft, end: bottomLeft))
    }

    func resolvedPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (x: Double, y: Double)? {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(point, owner: owner)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(line.start, owner: owner)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(line.end, owner: owner)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .circle(circle) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(circle.center, owner: owner)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(arc.center, owner: owner)
        case let .arcStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.startAngle, owner: owner)
        case let .arcEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSketchPointReference(owner)
            }
            return try pointOnArc(arc, angle: arc.endAngle, owner: owner)
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidSketchPointReference(owner)
            }
            return try resolvedPoint(spline.controlPoints[index], owner: owner)
        case .circleRadius, .arcRadius:
            return nil
        }
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    func pointOnArc(
        _ arc: SketchArc,
        angle: CADExpression,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let center = try resolvedPoint(arc.center, owner: owner)
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let resolvedAngle = try resolvedAngleValue(angle, owner: "\(owner) arc angle")
        return (
            x: center.x + cos(resolvedAngle) * radius,
            y: center.y + sin(resolvedAngle) * radius
        )
    }

    private func invalidSketchPointReference(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references an unsupported sketch point."
        )
    }

    func rectangleLineIDs(
        in sketch: Sketch
    ) throws -> (bottom: SketchEntityID, right: SketchEntityID, top: SketchEntityID, left: SketchEntityID)? {
        guard let bounds = try resolvedSketchBounds2D(sketch),
              sketch.entities.count == 4 else {
            return nil
        }
        var bottom: SketchEntityID?
        var right: SketchEntityID?
        var top: SketchEntityID?
        var left: SketchEntityID?
        let tolerance = 1.0e-9

        for (id, entity) in sketch.entities {
            guard case .line(let line) = entity else {
                return nil
            }
            let startX = try resolvedLengthValue(line.start.x, owner: "Rectangle line start x")
            let startY = try resolvedLengthValue(line.start.y, owner: "Rectangle line start y")
            let endX = try resolvedLengthValue(line.end.x, owner: "Rectangle line end x")
            let endY = try resolvedLengthValue(line.end.y, owner: "Rectangle line end y")
            if nearlyEqual(startY, bounds.minY, tolerance: tolerance),
               nearlyEqual(endY, bounds.minY, tolerance: tolerance) {
                bottom = id
            } else if nearlyEqual(startY, bounds.maxY, tolerance: tolerance),
                      nearlyEqual(endY, bounds.maxY, tolerance: tolerance) {
                top = id
            } else if nearlyEqual(startX, bounds.minX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.minX, tolerance: tolerance) {
                left = id
            } else if nearlyEqual(startX, bounds.maxX, tolerance: tolerance),
                      nearlyEqual(endX, bounds.maxX, tolerance: tolerance) {
                right = id
            } else {
                return nil
            }
        }

        guard let bottom,
              let right,
              let top,
              let left else {
            return nil
        }
        return (bottom, right, top, left)
    }

    func nearlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    func resolvedSketchBounds2D(
        _ sketch: Sketch
    ) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var points: [(x: Double, y: Double)] = []
        for entity in sketch.entities.values {
            for point in sketchPoints(in: entity) {
                points.append(
                    (
                        x: try resolvedLengthValue(point.x, owner: "Sketch point x"),
                        y: try resolvedLengthValue(point.y, owner: "Sketch point y")
                    )
                )
            }
        }
        guard let first = points.first else {
            return nil
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return (minX, minY, maxX, maxY)
    }

    private func sketchPoints(in entity: SketchEntity) -> [SketchPoint] {
        switch entity {
        case .point(let point):
            [point]
        case .line(let line):
            [line.start, line.end]
        case .circle(let circle):
            [circle.center]
        case .arc(let arc):
            [arc.center]
        case .spline(let spline):
            spline.controlPoints
        }
    }

    func isRectangleProfile(_ sketch: Sketch) -> Bool {
        guard sketch.entities.count == 4 else {
            return false
        }
        return sketch.entities.values.allSatisfy { entity in
            if case .line(_) = entity {
                return true
            }
            return false
        }
    }

    func singleCircleEntry(in sketch: Sketch) -> (id: SketchEntityID, circle: SketchCircle)? {
        var circleEntry: (id: SketchEntityID, circle: SketchCircle)?
        for (id, entity) in sketch.entities {
            guard case .circle(let circle) = entity else {
                return nil
            }
            guard circleEntry == nil else {
                return nil
            }
            circleEntry = (id, circle)
        }
        return circleEntry
    }

    public func validate(objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        try cadDocument.validate()
        try ruler.validate()
        guard ruler.displayUnit == displayUnit else {
            throw DocumentValidationError.invalidProductMetadata(
                "Document ruler display unit must match the document display unit."
            )
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
    }

}

private extension SketchEntity {
    var line: SketchLine? {
        if case .line(let line) = self {
            return line
        }
        return nil
    }

    var circle: SketchCircle? {
        if case .circle(let circle) = self {
            return circle
        }
        return nil
    }

    var arc: SketchArc? {
        if case .arc(let arc) = self {
            return arc
        }
        return nil
    }

    var spline: SketchSpline? {
        if case .spline(let spline) = self {
            return spline
        }
        return nil
    }
}
