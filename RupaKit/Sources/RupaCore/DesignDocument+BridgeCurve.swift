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
        let firstTension = try resolvedBridgeTension(
            firstEndpoint.tension,
            owner: "Bridge curve first tension"
        )
        let secondTension = try resolvedBridgeTension(
            secondEndpoint.tension,
            owner: "Bridge curve second tension"
        )
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
        if trimsSourceCurves {
            try validateBridgeCurveTrimDistinctSourceEntities(
                firstEndpoint: firstEndpoint,
                secondEndpoint: secondEndpoint
            )
            nextFirstEndpoint = try trimBridgeCurveSourceEndpoint(
                firstEndpoint,
                in: &sketch,
                owner: "Bridge curve first trim"
            )
            nextSecondEndpoint = try trimBridgeCurveSourceEndpoint(
                secondEndpoint,
                in: &sketch,
                owner: "Bridge curve second trim"
            )
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
        try validateBridgeContinuitySupport(
            first: firstSample,
            second: secondSample,
            continuity: continuity
        )

        let controlPoints = bridgeControlPoints(
            first: firstSample,
            firstTension: firstTension,
            second: secondSample,
            secondTension: secondTension
        )
        let spline = SketchSpline(controlPoints: controlPoints)
        try validateSpline(spline, owner: "Bridge curve")

        let bridgeID = SketchEntityID()
        sketch.entities[bridgeID] = .spline(spline)
        for constraint in bridgeOwnedConstraints(
            bridgeID: bridgeID,
            firstEndpoint: nextFirstEndpoint,
            secondEndpoint: nextSecondEndpoint,
            firstSample: firstSample,
            secondSample: secondSample,
            continuity: continuity
        ) {
            appendBridgeConstraint(constraint, to: &sketch)
        }
        let bridgeSource = BridgeCurveSource(
            featureID: featureID,
            entityID: bridgeID,
            firstEndpoint: nextFirstEndpoint,
            secondEndpoint: nextSecondEndpoint,
            continuity: continuity,
            trimsSourceCurves: trimsSourceCurves
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
        if let trimsSourceCurves,
           trimsSourceCurves == false,
           source.trimsSourceCurves {
            throw EditorError(
                code: .commandInvalid,
                message: "Bridge curve trim cannot be disabled after source curves have been trimmed."
            )
        }
        let nextSource = BridgeCurveSource(
            id: source.id,
            featureID: source.featureID,
            entityID: source.entityID,
            firstEndpoint: firstEndpoint ?? source.firstEndpoint,
            secondEndpoint: secondEndpoint ?? source.secondEndpoint,
            continuity: continuity ?? source.continuity,
            trimsSourceCurves: trimsSourceCurves ?? source.trimsSourceCurves
        )
        let firstTension = try resolvedBridgeTension(
            nextSource.firstEndpoint.tension,
            owner: "Bridge curve first tension"
        )
        let secondTension = try resolvedBridgeTension(
            nextSource.secondEndpoint.tension,
            owner: "Bridge curve second tension"
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
              case .spline = sketch.entities[source.entityID] else {
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
        let previousConstraints = bridgeOwnedConstraints(
            bridgeID: source.entityID,
            firstEndpoint: source.firstEndpoint,
            secondEndpoint: source.secondEndpoint,
            firstSample: previousFirstSample,
            secondSample: previousSecondSample,
            continuity: source.continuity
        )
        sketch.constraints.removeAll { previousConstraints.contains($0) }
        var resolvedNextSource = nextSource
        if resolvedNextSource.trimsSourceCurves {
            try validateBridgeCurveTrimDistinctSourceEntities(
                firstEndpoint: resolvedNextSource.firstEndpoint,
                secondEndpoint: resolvedNextSource.secondEndpoint
            )
            resolvedNextSource.firstEndpoint = try trimBridgeCurveSourceEndpoint(
                resolvedNextSource.firstEndpoint,
                in: &sketch,
                owner: "Bridge curve first trim"
            )
            resolvedNextSource.secondEndpoint = try trimBridgeCurveSourceEndpoint(
                resolvedNextSource.secondEndpoint,
                in: &sketch,
                owner: "Bridge curve second trim"
            )
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
        try validateBridgeContinuitySupport(
            first: firstSample,
            second: secondSample,
            continuity: resolvedNextSource.continuity
        )

        let spline = SketchSpline(controlPoints: bridgeControlPoints(
            first: firstSample,
            firstTension: firstTension,
            second: secondSample,
            secondTension: secondTension
        ))
        try validateSpline(spline, owner: "Bridge curve")

        sketch.entities[source.entityID] = .spline(spline)
        for constraint in bridgeOwnedConstraints(
            bridgeID: source.entityID,
            firstEndpoint: resolvedNextSource.firstEndpoint,
            secondEndpoint: resolvedNextSource.secondEndpoint,
            firstSample: firstSample,
            secondSample: secondSample,
            continuity: resolvedNextSource.continuity
        ) {
            appendBridgeConstraint(constraint, to: &sketch)
        }

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

    private func bridgeControlPoints(
        first: SketchCurveEndpointSample,
        firstTension: ResolvedBridgeCurveTension,
        second: SketchCurveEndpointSample,
        secondTension: ResolvedBridgeCurveTension
    ) -> [SketchPoint] {
        let p0 = first.sample.point
        let p6 = second.sample.point
        let chord = CADCore.Point2D(
            x: p6.x - p0.x,
            y: p6.y - p0.y
        )
        let chordLength = max(sqrt(chord.x * chord.x + chord.y * chord.y), 1.0e-9)
        let chordTangent = CADCore.Point2D(
            x: chord.x / chordLength,
            y: chord.y / chordLength
        )
        let jointFraction = firstTension.third / (firstTension.third + secondTension.third)
        let p3 = CADCore.Point2D(
            x: p0.x + chord.x * jointFraction,
            y: p0.y + chord.y * jointFraction
        )
        let p1 = CADCore.Point2D(
            x: p0.x + first.outgoingTangent.x * chordLength * firstTension.first / 6.0,
            y: p0.y + first.outgoingTangent.y * chordLength * firstTension.first / 6.0
        )
        let p2 = CADCore.Point2D(
            x: p3.x - chordTangent.x * chordLength * firstTension.second / 6.0,
            y: p3.y - chordTangent.y * chordLength * firstTension.second / 6.0
        )
        let p4 = CADCore.Point2D(
            x: p3.x + chordTangent.x * chordLength * secondTension.second / 6.0,
            y: p3.y + chordTangent.y * chordLength * secondTension.second / 6.0
        )
        let p5 = CADCore.Point2D(
            x: p6.x + second.outgoingTangent.x * chordLength * secondTension.first / 6.0,
            y: p6.y + second.outgoingTangent.y * chordLength * secondTension.first / 6.0
        )
        return [
            sketchPoint(x: p0.x, y: p0.y),
            sketchPoint(x: p1.x, y: p1.y),
            sketchPoint(x: p2.x, y: p2.y),
            sketchPoint(x: p3.x, y: p3.y),
            sketchPoint(x: p4.x, y: p4.y),
            sketchPoint(x: p5.x, y: p5.y),
            sketchPoint(x: p6.x, y: p6.y),
        ]
    }

    private struct ResolvedBridgeCurveTension {
        var first: Double
        var second: Double
        var third: Double
    }

    private func resolvedBridgeTension(
        _ tension: BridgeCurveTension,
        owner: String
    ) throws -> ResolvedBridgeCurveTension {
        let first = try resolvedPositiveScalarValue(tension.first, owner: "\(owner) 1")
        let second = try resolvedPositiveScalarValue(tension.second, owner: "\(owner) 2")
        let third = try resolvedPositiveScalarValue(tension.third, owner: "\(owner) 3")
        return ResolvedBridgeCurveTension(
            first: first,
            second: second,
            third: third
        )
    }

    private func bridgeContinuityConstraints(
        bridgeID: SketchEntityID,
        first: SketchCurveEndpointSample,
        second: SketchCurveEndpointSample,
        continuity: BridgeCurveContinuity
    ) -> [SketchConstraint] {
        return bridgeEndpointContinuityConstraints(
            bridgeID: bridgeID,
            bridgeEndpoint: .start,
            source: first,
            continuity: continuity.first
        ) + bridgeEndpointContinuityConstraints(
            bridgeID: bridgeID,
            bridgeEndpoint: .end,
            source: second,
            continuity: continuity.second
        )
    }

    private func bridgeEndpointContinuityConstraints(
        bridgeID: SketchEntityID,
        bridgeEndpoint: SketchSplineEndpoint,
        source: SketchCurveEndpointSample,
        continuity: BridgeCurveEndpointContinuity
    ) -> [SketchConstraint] {
        guard continuity != .g0 else {
            return []
        }
        let bridgeReference = SketchSplineEndpointReference(
            splineID: bridgeID,
            endpoint: bridgeEndpoint
        )
        switch source.kind {
        case .line(let lineID):
            switch continuity {
            case .g0:
                return []
            case .g1:
                return [
                    .splineEndpointTangent(
                        spline: bridgeID,
                        endpoint: bridgeEndpoint,
                        line: lineID
                    ),
                ]
            case .g2, .g3:
                return []
            }
        case .spline(let sourceReference):
            guard let sourceReference else {
                return []
            }
            switch continuity {
            case .g0:
                return []
            case .g1:
                return [
                    .tangentSplineEndpoints(
                        first: bridgeReference,
                        second: sourceReference
                    ),
                ]
            case .g2:
                return [
                    .smoothSplineEndpoints(
                        first: bridgeReference,
                        second: sourceReference
                    ),
                ]
            case .g3:
                return []
            }
        case .arc:
            return []
        }
    }

    private func bridgeOwnedConstraints(
        bridgeID: SketchEntityID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        firstSample: SketchCurveEndpointSample,
        secondSample: SketchCurveEndpointSample,
        continuity: BridgeCurveContinuity
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
                .splineControlPoint(entity: bridgeID, index: 6),
                secondReference
            ))
        }
        constraints += bridgeContinuityConstraints(
            bridgeID: bridgeID,
            first: firstSample,
            second: secondSample,
            continuity: continuity
        )
        return constraints
    }

    private func validateBridgeContinuitySupport(
        first: SketchCurveEndpointSample,
        second: SketchCurveEndpointSample,
        continuity: BridgeCurveContinuity
    ) throws {
        try validateBridgeEndpointContinuitySupport(
            first,
            continuity: continuity.first,
            owner: "Bridge curve first continuity"
        )
        try validateBridgeEndpointContinuitySupport(
            second,
            continuity: continuity.second,
            owner: "Bridge curve second continuity"
        )
    }

    private func validateBridgeEndpointContinuitySupport(
        _ sample: SketchCurveEndpointSample,
        continuity: BridgeCurveEndpointContinuity,
        owner: String
    ) throws {
        switch continuity {
        case .g0:
            return
        case .g1:
            guard supportsPersistentBridgeTangency(sample) else {
                throw unsupportedBridgeContinuity(
                    "\(owner) G1 currently requires a line or spline endpoint."
                )
            }
        case .g2:
            guard supportsPersistentBridgeSmoothness(sample) else {
                throw unsupportedBridgeContinuity(
                    "\(owner) G2 currently requires a spline endpoint."
                )
            }
        case .g3:
            throw unsupportedBridgeContinuity(
                "\(owner) G3 requires a higher-order bridge constraint that is not implemented yet."
            )
        }
    }

    private func supportsPersistentBridgeTangency(
        _ sample: SketchCurveEndpointSample
    ) -> Bool {
        switch sample.kind {
        case .line:
            sample.pointReference != nil
        case .spline(let sourceReference):
            sourceReference != nil && sample.pointReference != nil
        case .arc:
            false
        }
    }

    private func supportsPersistentBridgeSmoothness(
        _ sample: SketchCurveEndpointSample
    ) -> Bool {
        switch sample.kind {
        case .spline(let sourceReference):
            sourceReference != nil && sample.pointReference != nil
        case .line, .arc:
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
                try validateSpline(split.retained, owner: owner)
                return TrimmedBridgeCurveEndpointSource(
                    entity: .spline(split.retained),
                    endpointReference: .splineControlPoint(
                        entity: entityID,
                        index: split.retained.controlPoints.count - 1
                    )
                )
            }
            try validateSpline(split.new, owner: owner)
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

    private func unsupportedBridgeContinuity(_ message: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: message
        )
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

    private func appendBridgeConstraint(
        _ constraint: SketchConstraint,
        to sketch: inout Sketch
    ) {
        guard sketch.constraints.contains(constraint) == false else {
            return
        }
        sketch.constraints.append(constraint)
    }
}
