import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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

    }
