import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createBridgeCurve(
        featureID: FeatureID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        continuity: BridgeCurveContinuity,
        trimsSourceCurves: Bool = false,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let resolver = SketchCurveEndpointResolver()
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve requires an editable sketch feature."
            )
        }
        var nextFirstEndpoint = firstEndpoint
        var nextSecondEndpoint = secondEndpoint
        var trimRecord: BridgeCurveTrimRecord?
        if trimsSourceCurves {
            let trim = try trimBridgeCurveSources(first: firstEndpoint, second: secondEndpoint, in: &sketch)
            nextFirstEndpoint = trim.first
            nextSecondEndpoint = trim.second
            trimRecord = trim.record
        }
        guard let firstSample = try resolver.sample(
            for: nextFirstEndpoint,
            sketch: sketch,
            document: self
        ),
        let secondSample = try resolver.sample(
            for: nextSecondEndpoint,
            sketch: sketch,
            document: self
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
            )
        }
        try validateDistinctBridgeEndpointSamples(first: firstSample, second: secondSample)

        let spline = try bridgeSpline(
            first: firstSample,
            second: secondSample,
            continuity: continuity,
            firstTension: nextFirstEndpoint.tension,
            secondTension: nextSecondEndpoint.tension,
            sketch: sketch
        )
        try validateSplineForm(spline, owner: "Bridge curve")

        let bridgeID = SketchEntityID()
        sketch.entities[bridgeID] = .spline(spline)
        for constraint in bridgeOwnedConstraints(
            bridgeID: bridgeID,
            lastControlPointIndex: spline.controlPoints.count - 1,
            firstSample: firstSample,
            secondSample: secondSample
        ) {
            appendBridgeConstraint(constraint, to: &sketch)
        }
        let bridgeSource = BridgeCurveSource(
            featureID: featureID,
            entityID: bridgeID,
            firstEndpoint: nextFirstEndpoint,
            secondEndpoint: nextSecondEndpoint,
            continuity: continuity,
            trimsSourceCurves: trimsSourceCurves,
            trimRecord: trimRecord
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitBridgeCurve = false
        defer {
            if didCommitBridgeCurve == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources[bridgeSource.id] = bridgeSource

        if sketch.entities.count == 1 {
            try setSketchObjectType(
                featureID: featureID,
                typeID: .spline,
                objectRegistry: objectRegistry
            )
        } else {
            try markSketchObjectAsSourceEdited(featureID: featureID)
        }
        try commitSketchEntityEdit(
            featureID: featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Bridge curve creation"
        )
        didCommitBridgeCurve = true
        return bridgeID
    }

    public mutating func setBridgeCurveParameters(
        sourceID: BridgeCurveSourceID,
        firstEndpoint: BridgeCurveEndpoint? = nil,
        secondEndpoint: BridgeCurveEndpoint? = nil,
        continuity: BridgeCurveContinuity? = nil,
        trimsSourceCurves: Bool? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard let source = productMetadata.bridgeCurveSources[sourceID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve source could not be resolved."
            )
        }
        let untrims = trimsSourceCurves == false && source.trimsSourceCurves
        var nextSource = BridgeCurveSource(
            id: source.id,
            featureID: source.featureID,
            entityID: source.entityID,
            firstEndpoint: firstEndpoint ?? source.firstEndpoint,
            secondEndpoint: secondEndpoint ?? source.secondEndpoint,
            continuity: continuity ?? source.continuity,
            trimsSourceCurves: trimsSourceCurves ?? source.trimsSourceCurves,
            trimRecord: source.trimRecord
        )
        let resolver = SketchCurveEndpointResolver()
        guard bridgeEndpointReferencesEntity(nextSource.firstEndpoint, entityID: source.entityID) == false,
              bridgeEndpointReferencesEntity(nextSource.secondEndpoint, entityID: source.entityID) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoints must not reference the generated bridge spline."
            )
        }
        guard var feature = cadDocument.designGraph.nodes[source.featureID],
              case var .sketch(sketch) = feature.operation,
              case .spline(let previousBridge) = sketch.entities[source.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve source must point to an editable generated spline."
            )
        }
        guard let previousFirstSample = try resolver.sample(
            for: source.firstEndpoint,
            sketch: sketch,
            document: self
        ),
        let previousSecondSample = try resolver.sample(
            for: source.secondEndpoint,
            sketch: sketch,
            document: self
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
            )
        }
        removeBridgeOwnedConstraints(
            bridgeID: source.entityID,
            lastControlPointIndex: previousBridge.controlPoints.count - 1,
            firstSample: previousFirstSample,
            secondSample: previousSecondSample,
            from: &sketch
        )
        if untrims {
            try restoreBridgeCurveSources(of: &nextSource, in: &sketch)
        }
        var resolvedNextSource = nextSource
        if resolvedNextSource.trimsSourceCurves {
            let trim = try trimBridgeCurveSources(
                first: resolvedNextSource.firstEndpoint,
                second: resolvedNextSource.secondEndpoint,
                in: &sketch
            )
            resolvedNextSource.firstEndpoint = trim.first
            resolvedNextSource.secondEndpoint = trim.second
            if var record = source.trimRecord, source.trimsSourceCurves {
                // A retrim of trimmed sources keeps what they were before the first trim.
                record.trimmedEntities.merge(trim.record.trimmedEntities) { _, new in new }
                resolvedNextSource.trimRecord = record
            } else if !source.trimsSourceCurves {
                resolvedNextSource.trimRecord = trim.record
            }
        }
        guard let firstSample = try resolver.sample(
            for: resolvedNextSource.firstEndpoint,
            sketch: sketch,
            document: self
        ),
        let secondSample = try resolver.sample(
            for: resolvedNextSource.secondEndpoint,
            sketch: sketch,
            document: self
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
            )
        }
        try validateDistinctBridgeEndpointSamples(first: firstSample, second: secondSample)
        // The commit regenerates the bridge from the updated source: its spline, the constraints
        // it owns and the references to its ends follow from the control points stored now.

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitBridgeCurveUpdate = false
        defer {
            if didCommitBridgeCurveUpdate == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        productMetadata.bridgeCurveSources[sourceID] = resolvedNextSource
        try commitSketchEntityEdit(
            featureID: source.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Bridge curve parameter update"
        )
        didCommitBridgeCurveUpdate = true
    }

    /// The constraints a bridge owns: its end control points coincident with point-referenced
    /// source ends. Its continuity is not restated as sketch constraints: the source is its one
    /// authority, and a propagated continuity constraint would reshape the sources to fit the
    /// bridge instead of the bridge to fit them.
    func bridgeOwnedConstraints(
        bridgeID: SketchEntityID,
        lastControlPointIndex: Int,
        firstSample: SketchCurveEndpointSample,
        secondSample: SketchCurveEndpointSample
    ) -> [SketchConstraint] {
        var constraints: [SketchConstraint] = []
        if let firstReference = firstSample.pointReference {
            constraints.append(.coincident(
                .splineControlPoint(entity: bridgeID, index: 0),
                firstReference
            ))
        }
        if let secondReference = secondSample.pointReference {
            constraints.append(.coincident(
                .splineControlPoint(entity: bridgeID, index: lastControlPointIndex),
                secondReference
            ))
        }
        return constraints
    }

    /// Removes what a bridge owned: its end coincidences at `lastControlPointIndex` and every
    /// endpoint continuity constraint on it, which earlier generators added and a sketch
    /// constraint can no longer declare (`validateSketchConstraintOnBridgeCurves`).
    func removeBridgeOwnedConstraints(
        bridgeID: SketchEntityID,
        lastControlPointIndex: Int,
        firstSample: SketchCurveEndpointSample,
        secondSample: SketchCurveEndpointSample,
        from sketch: inout Sketch
    ) {
        let owned = bridgeOwnedConstraints(
            bridgeID: bridgeID,
            lastControlPointIndex: lastControlPointIndex,
            firstSample: firstSample,
            secondSample: secondSample
        )
        sketch.constraints.removeAll { constraint in
            owned.contains(constraint) || constraintStatesBridgeContinuity(constraint, bridgeID: bridgeID)
        }
    }

    func constraintStatesBridgeContinuity(_ constraint: SketchConstraint, bridgeID: SketchEntityID) -> Bool {
        switch constraint {
        case .splineEndpointTangent(let tangency):
            tangency.splineEndpoint.splineID == bridgeID
        case .tangentSplineEndpoints(let pair), .smoothSplineEndpoints(let pair):
            pair.first.splineID == bridgeID || pair.second.splineID == bridgeID
        case .smoothSplineControlPoint(let entity, _):
            entity == bridgeID
        case .coincident, .horizontal, .vertical, .parallel, .perpendicular, .equalLength, .tangent,
             .concentric, .equalRadius, .fixed:
            false
        }
    }

    private func validateDistinctBridgeEndpointSamples(
        first: SketchCurveEndpointSample,
        second: SketchCurveEndpointSample
    ) throws {
        let dx = first.sample.point.x - second.sample.point.x
        let dy = first.sample.point.y - second.sample.point.y
        guard hypot(dx, dy) > 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve endpoints must resolve to two distinct points."
            )
        }
    }

    private struct TrimmedBridgeCurveEndpointSource {
        var entity: SketchEntity
        var endpointReference: SketchReference
    }

    private func validateBridgeCurveTrimDistinctSourceEntities(
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint
    ) throws {
        guard bridgeCurveEndpointRequiresTrim(firstEndpoint) || bridgeCurveEndpointRequiresTrim(secondEndpoint),
              let firstEntityID = bridgeCurveEndpointEntityID(firstEndpoint),
              let secondEntityID = bridgeCurveEndpointEntityID(secondEndpoint),
              firstEntityID == secondEntityID else {
            return
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Bridge curve trim cannot rewrite a source curve referenced by both bridge endpoints in one command."
        )
    }

    private func bridgeCurveEndpointRequiresTrim(_ endpoint: BridgeCurveEndpoint) -> Bool {
        guard let parameter = endpoint.parameter else {
            return false
        }
        guard case .constant(let quantity) = parameter,
              quantity.kind == .scalar else {
            return true
        }
        return quantity.value > ModelingTolerance.standard.distance
            && quantity.value < 1.0 - ModelingTolerance.standard.distance
    }

    /// Trims a bridge's two source curves at its ends, returning the trimmed ends and what the
    /// trim replaced.
    private func trimBridgeCurveSources(
        first: BridgeCurveEndpoint,
        second: BridgeCurveEndpoint,
        in sketch: inout Sketch
    ) throws -> (first: BridgeCurveEndpoint, second: BridgeCurveEndpoint, record: BridgeCurveTrimRecord) {
        try validateBridgeCurveTrimDistinctSourceEntities(firstEndpoint: first, secondEndpoint: second)
        let entityIDs = [first, second].compactMap { bridgeCurveEndpointEntityID($0) }
        var untrimmed: [SketchEntityID: SketchEntity] = [:]
        for entityID in entityIDs { untrimmed[entityID] = sketch.entities[entityID] }
        let trimmedFirst = try trimBridgeCurveSourceEndpoint(first, in: &sketch, owner: "Bridge curve first trim")
        let trimmedSecond = try trimBridgeCurveSourceEndpoint(second, in: &sketch, owner: "Bridge curve second trim")
        var trimmed: [SketchEntityID: SketchEntity] = [:]
        for entityID in entityIDs { trimmed[entityID] = sketch.entities[entityID] }
        return (trimmedFirst, trimmedSecond, BridgeCurveTrimRecord(
            untrimmedFirstEndpoint: first,
            untrimmedSecondEndpoint: second,
            untrimmedEntities: untrimmed,
            trimmedEntities: trimmed
        ))
    }

    /// Turns Trim off: the source curves go back to what they were before the trim and the bridge
    /// joins its untrimmed ends, keeping its current tension and sense. Refused when the trim was
    /// not recorded or a trimmed curve was edited since, which the restore would undo.
    private func restoreBridgeCurveSources(of source: inout BridgeCurveSource, in sketch: inout Sketch) throws {
        guard let record = source.trimRecord else {
            throw EditorError(
                code: .commandInvalid,
                message: "This Bridge Curve's trim was made before Rupa kept the trimmed curves, so it cannot be turned off; undo it instead."
            )
        }
        for (entityID, trimmed) in record.trimmedEntities where sketch.entities[entityID] != trimmed {
            throw EditorError(
                code: .commandInvalid,
                message: "A curve this Bridge Curve trimmed was edited since, so its trim cannot be turned off without undoing that edit."
            )
        }
        for (entityID, untrimmed) in record.untrimmedEntities {
            sketch.entities[entityID] = untrimmed
        }
        func restored(_ untrimmed: BridgeCurveEndpoint, keeping current: BridgeCurveEndpoint) -> BridgeCurveEndpoint {
            var endpoint = untrimmed
            endpoint.reversesSense = current.reversesSense
            endpoint.tension = current.tension
            endpoint.trimSide = current.trimSide
            return endpoint
        }
        source.firstEndpoint = restored(record.untrimmedFirstEndpoint, keeping: source.firstEndpoint)
        source.secondEndpoint = restored(record.untrimmedSecondEndpoint, keeping: source.secondEndpoint)
        source.trimRecord = nil
    }

    private func trimBridgeCurveSourceEndpoint(
        _ endpoint: BridgeCurveEndpoint,
        in sketch: inout Sketch,
        owner: String
    ) throws -> BridgeCurveEndpoint {
        guard let parameterExpression = endpoint.parameter else {
            return endpoint
        }
        let parameter = try resolvedScalarValue(
            parameterExpression,
            owner: "\(owner) value"
        )
        guard parameter > ModelingTolerance.standard.distance,
              parameter < 1.0 - ModelingTolerance.standard.distance else {
            return endpoint
        }
        guard let entityID = bridgeCurveEndpointEntityID(endpoint),
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires a line, arc, or spline curve position."
            )
        }
        try validateBridgeCurveTrimCanRewriteEntity(
            entityID: entityID,
            sketch: sketch,
            owner: owner
        )
        let trimmed = try trimmedBridgeCurveEndpointSource(
            entity,
            entityID: entityID,
            parameter: parameter,
            trimSide: endpoint.trimSide,
            owner: owner
        )
        sketch.entities[entityID] = trimmed.entity
        return BridgeCurveEndpoint(
            reference: trimmed.endpointReference,
            reversesSense: adjustedReversesSenseAfterTrim(endpoint),
            trimSide: endpoint.trimSide,
            tension: endpoint.tension
        )
    }

    private func validateBridgeCurveTrimCanRewriteEntity(
        entityID: SketchEntityID,
        sketch: Sketch,
        owner: String
    ) throws {
        let hasRelatedConstraint = sketch.constraints.contains { constraint in
            sketchConstraint(constraint, references: entityID)
        }
        guard hasRelatedConstraint == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot rewrite a source curve that already has constraints."
            )
        }
        let hasRelatedDimension = sketch.dimensions.contains { dimension in
            sketchDimension(dimension, references: entityID)
        }
        guard hasRelatedDimension == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) cannot rewrite a source curve that already has dimensions."
            )
        }
    }

    private func trimmedBridgeCurveEndpointSource(
        _ entity: SketchEntity,
        entityID: SketchEntityID,
        parameter: Double,
        trimSide: BridgeCurveTrimSide,
        owner: String
    ) throws -> TrimmedBridgeCurveEndpointSource {
        switch entity {
        case .line(let line):
            let splitPoint = try splitPoint(
                on: line,
                fraction: parameter,
                owner: owner
            )
            if trimSide.keepsLowerParameterSide {
                let trimmed = SketchLine(start: line.start, end: splitPoint)
                _ = try resolvedLineMetrics(trimmed, owner: owner)
                return TrimmedBridgeCurveEndpointSource(
                    entity: .line(trimmed),
                    endpointReference: .lineEnd(entityID)
                )
            }
            let trimmed = SketchLine(start: splitPoint, end: line.end)
            _ = try resolvedLineMetrics(trimmed, owner: owner)
            return TrimmedBridgeCurveEndpointSource(
                entity: .line(trimmed),
                endpointReference: .lineStart(entityID)
            )
        case .arc(let arc):
            let split = try splitArc(arc, fraction: parameter, owner: owner)
            if trimSide.keepsLowerParameterSide {
                try validateArc(split.retained, owner: owner)
                return TrimmedBridgeCurveEndpointSource(
                    entity: .arc(split.retained),
                    endpointReference: .arcEnd(entityID)
                )
            }
            try validateArc(split.new, owner: owner)
            return TrimmedBridgeCurveEndpointSource(
                entity: .arc(split.new),
                endpointReference: .arcStart(entityID)
            )
        case .spline(let spline):
            let split = try splitSpline(spline, fraction: parameter, owner: owner)
            if trimSide.keepsLowerParameterSide {
                try validateSplineForm(split.retained, owner: owner)
                return TrimmedBridgeCurveEndpointSource(
                    entity: .spline(split.retained),
                    endpointReference: .splineControlPoint(
                        entity: entityID,
                        index: split.retained.controlPoints.count - 1
                    )
                )
            }
            try validateSplineForm(split.new, owner: owner)
            return TrimmedBridgeCurveEndpointSource(
                entity: .spline(split.new),
                endpointReference: .splineControlPoint(entity: entityID, index: 0)
            )
        case .point,
             .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line, arc, or spline curve position."
            )
        }
    }

    private func adjustedReversesSenseAfterTrim(_ endpoint: BridgeCurveEndpoint) -> Bool {
        if endpoint.trimSide.keepsLowerParameterSide {
            return endpoint.reversesSense
        }
        return !endpoint.reversesSense
    }

    private func bridgeCurveEndpointEntityID(_ endpoint: BridgeCurveEndpoint) -> SketchEntityID? {
        switch endpoint.reference {
        case let .entity(entityID),
             let .lineStart(entityID),
             let .lineEnd(entityID),
             let .arcStart(entityID),
             let .arcEnd(entityID),
             let .splineControlPoint(entityID, _):
            return entityID
        case .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    func bridgeEndpointReferencesEntity(
        _ reference: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch reference {
        case let .entity(referenceEntityID),
             let .lineStart(referenceEntityID),
             let .lineEnd(referenceEntityID),
             let .circleCenter(referenceEntityID),
             let .circleRadius(referenceEntityID),
             let .arcCenter(referenceEntityID),
             let .arcStart(referenceEntityID),
             let .arcEnd(referenceEntityID),
             let .arcRadius(referenceEntityID),
             let .splineControlPoint(referenceEntityID, _):
            referenceEntityID == entityID
        }
    }

    func bridgeEndpointReferencesEntity(
        _ endpoint: BridgeCurveEndpoint,
        entityID: SketchEntityID
    ) -> Bool {
        bridgeEndpointReferencesEntity(endpoint.reference, entityID: entityID)
    }

    func appendBridgeConstraint(
        _ constraint: SketchConstraint,
        to sketch: inout Sketch
    ) {
        guard sketch.constraints.contains(constraint) == false else {
            return
        }
        sketch.constraints.append(constraint)
    }
}
