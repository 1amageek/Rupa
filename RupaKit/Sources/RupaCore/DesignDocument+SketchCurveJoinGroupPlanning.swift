import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    private struct SketchCurveJoinEndpointSample {
        var reference: SketchReference
        var point: (x: Double, y: Double)
        var tangent: (x: Double, y: Double)
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

    }
