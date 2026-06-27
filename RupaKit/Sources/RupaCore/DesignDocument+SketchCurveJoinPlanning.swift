import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct SketchLineJoinPlan {
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

    struct SketchCurveGroupJoinPlan {
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

    private func resolvedJoinCurvePoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    func sketchLineJoinPlan(
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

    func sketchCurveGroupJoinPlan(
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
            let center = try resolvedJoinCurvePoint(arc.center, owner: owner)
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
        let firstStart = try resolvedJoinCurvePoint(first.start, owner: "\(owner) first start")
        let firstEnd = try resolvedJoinCurvePoint(first.end, owner: "\(owner) first end")
        let secondStart = try resolvedJoinCurvePoint(second.start, owner: "\(owner) second start")
        let secondEnd = try resolvedJoinCurvePoint(second.end, owner: "\(owner) second end")
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

    func sketchLineJoinPlan(
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

    func validateSketchLineJoin(
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

    func validateSketchCurveGroupJoin(
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

    func constraintsAfterSketchLineJoin(
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

    func constraintsAfterSketchCurveGroupJoin(
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

    func dimensionsAfterSketchLineJoin(
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

    func joinedCurveSourceIfPresent(
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

    func joinedCurveGroupSourceIfPresent(
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

    func validateSketchLineUnjoin(
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

    func validateSketchCurveGroupUnjoin(
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
        let firstStart = try resolvedJoinCurvePoint(first.start, owner: "\(owner) first start")
        let firstEnd = try resolvedJoinCurvePoint(first.end, owner: "\(owner) first end")
        let secondStart = try resolvedJoinCurvePoint(second.start, owner: "\(owner) second start")
        let secondEnd = try resolvedJoinCurvePoint(second.end, owner: "\(owner) second end")
        return squaredDistance(firstStart, secondStart) <= joinCurveEndpointToleranceSquared &&
            squaredDistance(firstEnd, secondEnd) <= joinCurveEndpointToleranceSquared
    }
}
