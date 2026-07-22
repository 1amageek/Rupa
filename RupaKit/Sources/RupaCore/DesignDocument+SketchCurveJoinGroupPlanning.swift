import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    private struct SketchCurveJoinEndpointSample {
        var reference: SketchReference
        var point: (x: Double, y: Double)
        var tangent: (x: Double, y: Double)
    }

    private enum SketchCurveJoinContinuityEndpoint {
        case line(SketchEntityID)
        case arc(SketchEntityID)
        case spline(SketchSplineEndpointReference)
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
        if let controlPointReference = componentID.sketchControlPointReference {
            guard controlPointReference.featureID == selection.featureID,
                  controlPointReference.entityID == selection.entityID else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) spline control-point target does not match the selected source curve."
                )
            }
            return [
                try joinCurveSplineEndpointReference(
                    controlPointIndex: controlPointReference.index,
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
        case .spline(let spline):
            guard spline.controlPoints.count >= 2 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a spline with editable endpoints."
                )
            }
            return [
                .splineControlPoint(entity: selection.entityID, index: 0),
                .splineControlPoint(entity: selection.entityID, index: spline.controlPoints.count - 1),
            ]
        case .point,
             .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves composite join currently supports source line, arc, and spline endpoints."
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
                message: "Join Curves composite join currently supports source line, arc, and spline endpoints."
            )
        }
    }

        private func joinCurveSplineEndpointReference(
        controlPointIndex: Int,
        selection: EditableSketchEntitySelection,
        owner: String
    ) throws -> SketchReference {
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) control-point target requires a source spline."
            )
        }
        guard spline.controlPoints.indices.contains(controlPointIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing spline control point."
            )
        }
        guard controlPointIndex == 0 || controlPointIndex == spline.controlPoints.count - 1 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a spline endpoint control point."
            )
        }
        return .splineControlPoint(entity: selection.entityID, index: controlPointIndex)
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
            guard let continuityConstraint = try joinCurveGroupContinuityConstraint(join, sketch: sketch) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves G1 continuity currently supports line-arc, spline-line, and spline-spline endpoint pairs."
                )
            }
            if case .tangent = continuityConstraint {
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
            }
        case .g2:
            guard try joinCurveGroupContinuityConstraint(join, sketch: sketch) != nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves G2 continuity currently requires two spline endpoints."
                )
            }
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
        case .splineControlPoint(let entityID, let index):
            guard case .spline(let spline) = sketch.entities[entityID],
                  index == 0 || index == spline.controlPoints.count - 1 else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) requires a source spline endpoint."
                )
            }
            let controlPoints = try spline.controlPoints.map {
                let point = try resolvedJoinCurvePoint($0, owner: owner)
                return CADCore.Point2D(x: point.x, y: point.y)
            }
            let parameter = index == 0 ? 0.0 : 1.0
            guard let sample = sampler.splineSample(
                for: controlPoints,
                parameter: parameter
            ) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) requires a non-degenerate source spline endpoint."
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
             .arcRadius:
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

        func applySketchCurveGroupJoinConstraints(
        to sketch: inout Sketch,
        join: SketchCurveGroupJoinPlan,
    ) throws -> [SketchConstraint] {
        if sketch.constraints.contains(where: { constraint in
            joinConstraintMatchesEndpoints(
                constraint,
                first: join.firstJoinedReference,
                second: join.secondJoinedReference
            )
        }) == false {
            sketch.constraints.append(.coincident(join.firstJoinedReference, join.secondJoinedReference))
        }
        if let continuityConstraint = try joinCurveGroupContinuityConstraint(join, sketch: sketch),
           sketch.constraints.contains(where: { constraint in
               joinConstraintMatchesContinuity(constraint, continuityConstraint: continuityConstraint)
           }) == false {
            switch continuityConstraint {
            case .splineEndpointTangent,
                 .tangentSplineEndpoints,
                 .smoothSplineEndpoints:
                let constraintPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
                try constraintPropagator.satisfyAddingConstraint(
                    continuityConstraint,
                    in: &sketch,
                    owner: "Join Curves"
                )
            case .tangent:
                sketch.constraints.append(continuityConstraint)
            case .coincident,
                 .fixed,
                 .horizontal,
                 .vertical,
                 .parallel,
                 .perpendicular,
                 .equalLength,
                 .concentric,
                 .equalRadius,
                 .smoothSplineControlPoint:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Join Curves built an unsupported continuity constraint."
                )
            }
        }
        return sketch.constraints
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

        private func joinCurveGroupContinuityConstraint(
        _ join: SketchCurveGroupJoinPlan,
        sketch: Sketch
    ) throws -> SketchConstraint? {
        let firstEndpoint = try joinCurveContinuityEndpoint(
            for: join.firstJoinedReference,
            sketch: sketch
        )
        let secondEndpoint = try joinCurveContinuityEndpoint(
            for: join.secondJoinedReference,
            sketch: sketch
        )
        switch join.continuity {
        case .g0:
            return nil
        case .g1:
            switch (firstEndpoint, secondEndpoint) {
            case (.line(let lineID), .arc(let arcID)):
                return .tangent(try joinLineCircularTangency(
                    lineID: lineID,
                    circularID: arcID,
                    sketch: sketch
                ))
            case (.arc(let arcID), .line(let lineID)):
                return .tangent(try joinLineCircularTangency(
                    lineID: lineID,
                    circularID: arcID,
                    sketch: sketch
                ))
            case (.spline(let splineEndpoint), .line(let lineID)),
                 (.line(let lineID), .spline(let splineEndpoint)):
                return .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                    splineEndpoint: splineEndpoint,
                    line: lineID,
                    orientation: try joinSplineLineTangentOrientation(
                        splineEndpoint: splineEndpoint,
                        lineID: lineID,
                        sketch: sketch
                    )
                ))
            case (.spline(let first), .spline(let second)):
                return .tangentSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: first,
                    second: second,
                    orientation: try joinSplineEndpointTangentOrientation(
                        first: first,
                        second: second,
                        sketch: sketch
                    )
                ))
            case (.line, .line),
                 (.arc, .arc),
                 (.arc, .spline),
                 (.spline, .arc):
                return nil
            }
        case .g2:
            switch (firstEndpoint, secondEndpoint) {
            case (.spline(let first), .spline(let second)):
                return .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: first,
                    second: second,
                    orientation: try joinSplineEndpointTangentOrientation(
                        first: first,
                        second: second,
                        sketch: sketch
                    )
                ))
            case (.line, _),
                 (.arc, _),
                 (.spline, .line),
                 (.spline, .arc):
                return nil
            }
        }
    }

        private func joinCurveContinuityEndpoint(
        for reference: SketchReference,
        sketch: Sketch
    ) throws -> SketchCurveJoinContinuityEndpoint {
        guard let entityID = joinedCurveReferenceEntityID(reference),
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves continuity requires existing source curve entities."
            )
        }
        switch (reference, entity) {
        case (.lineStart, .line),
             (.lineEnd, .line):
            return .line(entityID)
        case (.arcStart, .arc),
             (.arcEnd, .arc):
            return .arc(entityID)
        case (.splineControlPoint(_, let index), .spline(let spline)):
            if index == 0 {
                return .spline(SketchSplineEndpointReference(splineID: entityID, endpoint: .start))
            }
            if index == spline.controlPoints.count - 1 {
                return .spline(SketchSplineEndpointReference(splineID: entityID, endpoint: .end))
            }
            throw EditorError(
                code: .commandInvalid,
                message: "Join Curves continuity requires spline endpoint control points."
            )
        case (.entity, _),
             (.circleCenter, _),
             (.circleRadius, _),
             (.arcCenter, _),
             (.arcRadius, _),
             (.lineStart, _),
             (.lineEnd, _),
             (.arcStart, _),
             (.arcEnd, _),
             (.splineControlPoint, _):
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves continuity requires source line, arc, or spline endpoint references."
            )
        }
    }

        private func joinConstraintMatchesContinuity(
        _ constraint: SketchConstraint,
        continuityConstraint: SketchConstraint
    ) -> Bool {
        switch (constraint, continuityConstraint) {
        case let (.tangent(existing), .tangent(expected)):
            return existing == expected
        case let (
            .splineEndpointTangent(existing),
            .splineEndpointTangent(expected)
        ):
            return existing == expected
        case let (
            .tangentSplineEndpoints(existing),
            .tangentSplineEndpoints(expected)
        ),
        let (
            .smoothSplineEndpoints(existing),
            .smoothSplineEndpoints(expected)
        ):
            return existing == expected || (
                existing.orientation == expected.orientation &&
                existing.first == expected.second &&
                existing.second == expected.first
            )
        default:
            return false
        }
    }

    private func joinLineCircularTangency(
        lineID: SketchEntityID,
        circularID: SketchEntityID,
        sketch: Sketch
    ) throws -> SketchTangencyConstraint {
        guard case .line(let line) = sketch.entities[lineID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires an existing line for tangent continuity."
            )
        }
        let center: SketchPoint
        switch sketch.entities[circularID] {
        case .circle(let circle):
            center = circle.center
        case .arc(let arc):
            center = arc.center
        default:
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires an existing circular curve for tangent continuity."
            )
        }
        let start = try resolvedJoinCurvePoint(line.start, owner: "Join Curves tangent line start")
        let end = try resolvedJoinCurvePoint(line.end, owner: "Join Curves tangent line end")
        let resolvedCenter = try resolvedJoinCurvePoint(center, owner: "Join Curves tangent circle center")
        let cross = (end.x - start.x) * (resolvedCenter.y - start.y) -
            (end.y - start.y) * (resolvedCenter.x - start.x)
        return .lineCircular(
            line: lineID,
            circular: circularID,
            side: cross >= 0.0 ? .left : .right
        )
    }

    private func joinSplineLineTangentOrientation(
        splineEndpoint: SketchSplineEndpointReference,
        lineID: SketchEntityID,
        sketch: Sketch
    ) throws -> SketchTangentOrientation {
        let splineReference = try joinSplineSketchReference(splineEndpoint, sketch: sketch)
        let lineReference: SketchReference = .lineStart(lineID)
        let splineSample = try joinCurveEndpointSample(
            splineReference,
            sketch: sketch,
            owner: "Join Curves spline tangent"
        )
        let lineSample = try joinCurveEndpointSample(
            lineReference,
            sketch: sketch,
            owner: "Join Curves line tangent"
        )
        return joinTangentOrientation(splineSample.tangent, lineSample.tangent)
    }

    private func joinSplineEndpointTangentOrientation(
        first: SketchSplineEndpointReference,
        second: SketchSplineEndpointReference,
        sketch: Sketch
    ) throws -> SketchTangentOrientation {
        let firstSample = try joinCurveEndpointSample(
            try joinSplineSketchReference(first, sketch: sketch),
            sketch: sketch,
            owner: "Join Curves first spline tangent"
        )
        let secondSample = try joinCurveEndpointSample(
            try joinSplineSketchReference(second, sketch: sketch),
            sketch: sketch,
            owner: "Join Curves second spline tangent"
        )
        return joinTangentOrientation(firstSample.tangent, secondSample.tangent)
    }

    private func joinSplineSketchReference(
        _ endpoint: SketchSplineEndpointReference,
        sketch: Sketch
    ) throws -> SketchReference {
        guard case .spline(let spline) = sketch.entities[endpoint.splineID],
              spline.controlPoints.isEmpty == false else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Join Curves requires an existing spline endpoint for tangent continuity."
            )
        }
        let index = endpoint.endpoint == .start ? 0 : spline.controlPoints.count - 1
        return .splineControlPoint(entity: endpoint.splineID, index: index)
    }

    private func joinTangentOrientation(
        _ first: (x: Double, y: Double),
        _ second: (x: Double, y: Double)
    ) -> SketchTangentOrientation {
        first.x * second.x + first.y * second.y >= 0.0 ? .aligned : .opposed
    }

        private func joinedCurveReferenceEntityID(_ reference: SketchReference) -> SketchEntityID? {
        switch reference {
        case .lineStart(let entityID),
             .lineEnd(let entityID),
             .arcStart(let entityID),
             .arcEnd(let entityID),
             .splineControlPoint(let entityID, _):
            return entityID
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    }
