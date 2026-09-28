import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Align on two curves: the second curve's end nearest the first is aligned with the first's
    /// nearest end, as Align Vertex on those two ends.
    public mutating func alignSketchCurveEnds(
        first: SelectionTarget,
        second: SelectionTarget,
        options: SketchVertexAlignmentOptions = SketchVertexAlignmentOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let ends = try bridgeEndpoints(for: [first, second])
        func endTarget(_ reference: SketchReference, of target: SelectionTarget) throws -> SelectionTarget {
            let component: SelectionComponentID = switch reference {
            case .lineStart(let id): .sketchPointHandle(featureID: ends.featureID, entityID: id, handle: .lineStart)
            case .lineEnd(let id): .sketchPointHandle(featureID: ends.featureID, entityID: id, handle: .lineEnd)
            case .arcStart(let id): .sketchPointHandle(featureID: ends.featureID, entityID: id, handle: .arcStart)
            case .arcEnd(let id): .sketchPointHandle(featureID: ends.featureID, entityID: id, handle: .arcEnd)
            case .splineControlPoint(let id, let index): .sketchControlPoint(featureID: ends.featureID, entityID: id, index: index)
            case .entity(let id): .sketchPointHandle(featureID: ends.featureID, entityID: id, handle: .point)
            case .circleCenter, .circleRadius, .arcCenter, .arcRadius:
                throw EditorError(code: .commandInvalid, message: "Align aligns curve ends.")
            }
            return SelectionTarget(sceneNodeID: target.sceneNodeID, component: .sketchEntity(component))
        }
        try alignSketchVertex(
            target: endTarget(ends.second.reference, of: second),
            reference: endTarget(ends.first.reference, of: first),
            options: options,
            objectRegistry: objectRegistry
        )
    }

    public mutating func alignSketchVertex(
        target: SelectionTarget,
        reference: SelectionTarget,
        options: SketchVertexAlignmentOptions = SketchVertexAlignmentOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        try validateSketchVertexAlignmentOptionsSupported(options)
        let targetPoint = try sketchVertexAlignmentPoint(
            for: target,
            role: "target"
        )
        if let parameter = options.referenceParameter {
            try alignSketchVertex(targetPoint, toCurve: reference, at: parameter, options: options, objectRegistry: objectRegistry)
            return
        }
        let referencePoint = try sketchVertexAlignmentPoint(
            for: reference,
            role: "reference"
        )
        guard targetPoint.featureID == referencePoint.featureID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex currently requires target and reference vertices from the same source sketch."
            )
        }
        guard targetPoint.reference != referencePoint.reference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex requires distinct target and reference vertices."
            )
        }
        var feature = targetPoint.feature
        var sketch = targetPoint.sketch
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        let coincidentConstraint = SketchConstraint.coincident(
            referencePoint.reference,
            targetPoint.reference
        )
        try validateSketchConstraintOnBridgeCurves(
            coincidentConstraint,
            featureID: targetPoint.featureID,
            sketch: sketch,
            owner: "Align Vertex"
        )
        if sketchAlignmentConstraintExists(coincidentConstraint, in: sketch.constraints) {
            try pointPropagator.propagate(
                from: referencePoint.reference,
                in: &sketch,
                owner: "Align Vertex"
            )
        } else {
            try pointPropagator.satisfyAddingConstraint(
                coincidentConstraint,
                in: &sketch,
                owner: "Align Vertex"
            )
        }

        if options.continuity != .g0,
           try sketchVertexAlignmentContinuityConstraint(target: targetPoint, reference: referencePoint, continuity: options.continuity) == nil {
            // No sketch constraint holds this continuity between these curves: the target end is
            // aligned to the reference end's tangent and curvature once, its position still held.
            guard let frame = try sketchAlignmentFrame(atEnd: referencePoint.reference, in: sketch) else {
                throw unsupportedSketchVertexAlignmentContinuity("G1 and G2 need a reference curve end.")
            }
            try alignEnd(targetPoint, to: frame, continuity: options.continuity, handleDistance: options.targetContinuityDistance, in: &sketch, pointPropagator: pointPropagator)
        } else if options.continuity != .g0,
                  let continuityConstraint = try sketchVertexAlignmentContinuityConstraint(
                      target: targetPoint,
                      reference: referencePoint,
                      continuity: options.continuity
                  ) {
            try validateSketchConstraintOnBridgeCurves(
                continuityConstraint,
                featureID: targetPoint.featureID,
                sketch: sketch,
                owner: "Align Vertex"
            )
            if sketchAlignmentConstraintExists(continuityConstraint, in: sketch.constraints) == false {
                try pointPropagator.satisfyAddingConstraint(
                    continuityConstraint,
                    in: &sketch,
                    owner: "Align Vertex"
                )
            }
        }
        try applySketchVertexAlignmentContinuityDistances(
            options,
            target: targetPoint,
            reference: referencePoint,
            sketch: &sketch,
            pointPropagator: pointPropagator
        )

        try commitSketchEntityEdit(
            featureID: targetPoint.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Align Vertex"
        )
    }

    private struct SketchVertexAlignmentPoint {
        var featureID: FeatureID
        var entityID: SketchEntityID
        var feature: FeatureNode
        var sketch: Sketch
        var entity: SketchEntity
        var reference: SketchReference
        var endpoint: SketchVertexAlignmentEndpoint?
    }

    private enum SketchVertexAlignmentEndpoint {
        case line(SketchEntityID)
        case circular(SketchEntityID)
        case spline(SketchSplineEndpointReference)
    }

    private func sketchVertexAlignmentPoint(
        for target: SelectionTarget,
        role: String
    ) throws -> SketchVertexAlignmentPoint {
        let operationName = "Align Vertex \(role)"
        guard let sceneNode = productMetadata.sceneNodes[target.sceneNodeID],
              sceneNode.reference?.kind == .sketch,
              let featureID = sceneNode.reference?.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch scene node."
            )
        }
        guard case .sketchEntity(let componentID) = target.component,
              let pointReference = componentID.sketchPointReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a sketch point handle or spline control point target."
            )
        }
        guard pointReference.featureID == featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) selection target does not belong to the scene node sketch."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an editable sketch feature."
            )
        }
        let entityID = entityID(for: pointReference.reference)
        guard let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires an existing sketch entity."
            )
        }
        guard try resolvedPoint(pointReference.reference, in: sketch, owner: operationName) != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) requires a point-backed sketch reference."
            )
        }
        let endpoint = try sketchVertexAlignmentEndpoint(
            for: pointReference.reference,
            in: sketch,
            role: role
        )
        guard endpoint != nil || sketchVertexAlignmentIsStandalonePoint(
            pointReference.reference,
            in: sketch
        ) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a source point entity, line endpoint, arc endpoint, or spline endpoint control point."
            )
        }
        return SketchVertexAlignmentPoint(
            featureID: featureID,
            entityID: entityID,
            feature: feature,
            sketch: sketch,
            entity: entity,
            reference: pointReference.reference,
            endpoint: endpoint
        )
    }

    private func sketchVertexAlignmentIsStandalonePoint(
        _ reference: SketchReference,
        in sketch: Sketch
    ) -> Bool {
        guard case .entity(let entityID) = reference,
              case .point = sketch.entities[entityID] else {
            return false
        }
        return true
    }

    private func validateSketchVertexAlignmentOptionsSupported(
        _ options: SketchVertexAlignmentOptions
    ) throws {
        if (options.targetContinuityDistance != nil || options.referenceContinuityDistance != nil) &&
            options.continuity == .g0 {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex continuity distance controls require G1 or G2 continuity."
            )
        }
    }

    private func applySketchVertexAlignmentContinuityDistances(
        _ options: SketchVertexAlignmentOptions,
        target: SketchVertexAlignmentPoint,
        reference: SketchVertexAlignmentPoint,
        sketch: inout Sketch,
        pointPropagator: SketchPointConstraintPropagator
    ) throws {
        let targetDistance = try options.targetContinuityDistance.map {
            try resolvedPositiveLengthValue($0, owner: "Align Vertex target continuity distance")
        }
        let referenceDistance = try options.referenceContinuityDistance.map {
            try resolvedPositiveLengthValue($0, owner: "Align Vertex reference continuity distance")
        }
        guard targetDistance != nil || referenceDistance != nil else {
            return
        }
        if options.continuity == .g2,
           let targetDistance,
           let referenceDistance,
           abs(targetDistance - referenceDistance) > 1.0e-9 {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex G2 continuity requires matching target and reference continuity distances."
            )
        }
        switch options.continuity {
        case .g0:
            return
        case .g1:
            if let referenceDistance {
                try applySketchVertexAlignmentContinuityDistance(
                    referenceDistance,
                    to: reference,
                    in: &sketch,
                    pointPropagator: pointPropagator
                )
            }
            if let targetDistance {
                try applySketchVertexAlignmentContinuityDistance(
                    targetDistance,
                    to: target,
                    in: &sketch,
                    pointPropagator: pointPropagator
                )
            }
        case .g2:
            if let targetDistance {
                try applySketchVertexAlignmentContinuityDistance(
                    targetDistance,
                    to: target,
                    in: &sketch,
                    pointPropagator: pointPropagator
                )
            } else if let referenceDistance {
                try applySketchVertexAlignmentContinuityDistance(
                    referenceDistance,
                    to: reference,
                    in: &sketch,
                    pointPropagator: pointPropagator
                )
            }
        }
    }

    private func applySketchVertexAlignmentContinuityDistance(
        _ distance: Double,
        to point: SketchVertexAlignmentPoint,
        in sketch: inout Sketch,
        pointPropagator: SketchPointConstraintPropagator
    ) throws {
        guard case .spline(let endpointReference) = point.endpoint else {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex continuity distance controls require spline endpoints."
            )
        }
        let indexes = try sketchVertexAlignmentSplineEndpointIndexes(
            endpointReference,
            in: sketch
        )
        let handleReference = SketchReference.splineControlPoint(
            entity: endpointReference.splineID,
            index: indexes.handleIndex
        )
        guard sketch.constraints.contains(.fixed(handleReference)) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex cannot move a fixed spline continuity handle."
            )
        }
        guard case .spline(var spline) = sketch.entities[endpointReference.splineID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Align Vertex continuity distance requires a source spline endpoint."
            )
        }
        let endpoint = try resolvedPoint(
            .splineControlPoint(entity: endpointReference.splineID, index: indexes.endpointIndex),
            in: sketch,
            owner: "Align Vertex continuity endpoint"
        )
        let handle = try resolvedPoint(
            handleReference,
            in: sketch,
            owner: "Align Vertex continuity handle"
        )
        guard let endpoint,
              let handle else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Align Vertex continuity distance requires point-backed spline handles."
            )
        }
        let vector = (x: handle.x - endpoint.x, y: handle.y - endpoint.y)
        let currentDistance = sqrt(vector.x * vector.x + vector.y * vector.y)
        guard currentDistance > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex continuity handle must not collapse onto its endpoint."
            )
        }
        let scale = distance / currentDistance
        spline.controlPoints[indexes.handleIndex] = SketchPoint(
            x: .length(endpoint.x + vector.x * scale, .meter),
            y: .length(endpoint.y + vector.y * scale, .meter)
        )
        sketch.entities[endpointReference.splineID] = .spline(spline)
        try pointPropagator.propagate(
            from: handleReference,
            in: &sketch,
            owner: "Align Vertex"
        )
    }

    private func sketchVertexAlignmentSplineEndpointIndexes(
        _ reference: SketchSplineEndpointReference,
        in sketch: Sketch
    ) throws -> (endpointIndex: Int, handleIndex: Int) {
        guard case .spline(let spline) = sketch.entities[reference.splineID],
              spline.controlPoints.count >= 2 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Align Vertex continuity distance requires a source spline endpoint."
            )
        }
        switch reference.endpoint {
        case .start:
            return (endpointIndex: 0, handleIndex: 1)
        case .end:
            return (
                endpointIndex: spline.controlPoints.count - 1,
                handleIndex: spline.controlPoints.count - 2
            )
        }
    }

    private func sketchVertexAlignmentEndpoint(
        for reference: SketchReference,
        in sketch: Sketch,
        role: String
    ) throws -> SketchVertexAlignmentEndpoint? {
        switch reference {
        case .lineStart(let entityID),
             .lineEnd(let entityID):
            guard case .line = sketch.entities[entityID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Align Vertex \(role) line endpoint requires a line entity."
                )
            }
            return .line(entityID)
        case .arcStart(let entityID),
             .arcEnd(let entityID):
            guard case .arc = sketch.entities[entityID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Align Vertex \(role) arc endpoint requires an arc entity."
                )
            }
            return .circular(entityID)
        case .splineControlPoint(let entityID, let index):
            guard case .spline(let spline) = sketch.entities[entityID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Align Vertex \(role) spline control point requires a spline entity."
                )
            }
            if index == 0 {
                return .spline(SketchSplineEndpointReference(splineID: entityID, endpoint: .start))
            }
            if index == spline.controlPoints.count - 1 {
                return .spline(SketchSplineEndpointReference(splineID: entityID, endpoint: .end))
            }
            return nil
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return nil
        }
    }

    /// The sketch constraint that holds `continuity` between the two ends, or nil when none
    /// expresses it for these curves (their ends are then aligned once by `alignEnd`).
    private func sketchVertexAlignmentContinuityConstraint(
        target: SketchVertexAlignmentPoint,
        reference: SketchVertexAlignmentPoint,
        continuity: SketchVertexAlignmentContinuity
    ) throws -> SketchConstraint? {
        switch continuity {
        case .g0:
            return .coincident(reference.reference, target.reference)
        case .g1:
            guard let targetEndpoint = target.endpoint,
                  let referenceEndpoint = reference.endpoint else {
                throw unsupportedSketchVertexAlignmentContinuity(
                    "G1 continuity requires target and reference curve endpoints."
                )
            }
            switch (targetEndpoint, referenceEndpoint) {
            case (.line(let targetLineID), .line(let referenceLineID)):
                return .parallel(referenceLineID, targetLineID)
            case (.line(let targetLineID), .circular(let referenceCircularID)):
                return .tangent(.lineCircular(
                    line: targetLineID,
                    circular: referenceCircularID,
                    side: try lineCircularTangencySide(
                        lineID: targetLineID,
                        circularID: referenceCircularID,
                        in: target.sketch
                    )
                ))
            case (.circular(let targetCircularID), .line(let referenceLineID)):
                return .tangent(.lineCircular(
                    line: referenceLineID,
                    circular: targetCircularID,
                    side: try lineCircularTangencySide(
                        lineID: referenceLineID,
                        circularID: targetCircularID,
                        in: target.sketch
                    )
                ))
            case (.spline(let targetEndpoint), .line(let referenceLineID)):
                return .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                    splineEndpoint: targetEndpoint,
                    line: referenceLineID,
                    orientation: .aligned
                ))
            case (.spline(let targetEndpoint), .spline(let referenceEndpoint)):
                return .tangentSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: referenceEndpoint,
                    second: targetEndpoint,
                    orientation: referenceEndpoint.endpoint == targetEndpoint.endpoint
                        ? .opposed
                        : .aligned
                ))
            case (.line, .spline),
                 (.circular, .circular),
                 (.circular, .spline),
                 (.spline, .circular):
                return nil
            }
        case .g2:
            guard let targetEndpoint = target.endpoint,
                  let referenceEndpoint = reference.endpoint else {
                throw unsupportedSketchVertexAlignmentContinuity(
                    "G2 continuity requires target and reference spline endpoints."
                )
            }
            switch (targetEndpoint, referenceEndpoint) {
            case (.spline(let targetEndpoint), .spline(let referenceEndpoint)):
                return .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
                    first: referenceEndpoint,
                    second: targetEndpoint,
                    orientation: referenceEndpoint.endpoint == targetEndpoint.endpoint
                        ? .opposed
                        : .aligned
                ))
            case (.line, _),
                 (.circular, _),
                 (.spline, .line),
                 (.spline, .circular):
                return nil
            }
        }
    }

    /// Where and how a reference curve runs at the point a target end aligns to: its point, unit
    /// tangent, curvature vector (direction-free) and, at a curve end, the direction pointing past
    /// that end.
    private struct SketchAlignmentFrame {
        var point: Point2D
        var tangent: Point2D
        var curvatureVector: Point2D
        var outgoing: Point2D?
    }

    private func sketchAlignmentFrame(atEnd reference: SketchReference, in sketch: Sketch) throws -> SketchAlignmentFrame? {
        guard let sample = try SketchCurveEndpointResolver().sample(for: reference, sketch: sketch, document: self) else {
            return nil
        }
        return SketchAlignmentFrame(
            point: sample.sample.point,
            tangent: sample.sample.tangent,
            curvatureVector: Point2D(x: sample.sample.curvature * sample.sample.normal.x, y: sample.sample.curvature * sample.sample.normal.y),
            outgoing: sample.outgoingTangent
        )
    }

    /// Align Vertex with a Parameter: the target end moves to the point at `parameter` (the
    /// fraction over the reference curve's parameter, so 0.5 is not always its middle) and, for
    /// G1 or G2, takes the curve's tangent and curvature there. No sketch reference names a point
    /// inside a curve, so the alignment is made once and not held.
    private mutating func alignSketchVertex(
        _ targetPoint: SketchVertexAlignmentPoint,
        toCurve reference: SelectionTarget,
        at parameter: CADExpression,
        options: SketchVertexAlignmentOptions,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let owner = "Align Vertex"
        guard case .sketchEntity(let componentID) = reference.component,
              let curve = componentID.sketchEntityReference,
              componentID.sketchPointHandleReference == nil,
              componentID.sketchControlPointReference == nil else {
            throw EditorError(code: .commandInvalid, message: "\(owner) with a Parameter takes a reference curve.")
        }
        guard curve.featureID == targetPoint.featureID, curve.entityID != targetPoint.entityID else {
            throw EditorError(code: .commandInvalid, message: "\(owner) aligns to another curve of the same sketch.")
        }
        try validateNotGeneratedBridgeCurve(featureID: targetPoint.featureID, entityID: targetPoint.entityID, operationName: owner)
        var sketch = targetPoint.sketch
        guard let sample = try SketchCurveEndpointResolver().sample(
            for: BridgeCurveEndpoint(reference: .entity(curve.entityID), parameter: parameter),
            sketch: sketch,
            document: self
        ) else {
            throw EditorError(code: .commandInvalid, message: "\(owner) aligns to a line, arc or spline.")
        }
        let frame = SketchAlignmentFrame(
            point: sample.sample.point,
            tangent: sample.sample.tangent,
            curvatureVector: Point2D(x: sample.sample.curvature * sample.sample.normal.x, y: sample.sample.curvature * sample.sample.normal.y),
            outgoing: nil
        )
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        // Moved as a coincidence with a fixed point there would move it, through every constraint
        // on the target; the helper point and its constraints then go.
        let helperID = SketchEntityID()
        let helper = SketchReference.entity(helperID)
        sketch.entities[helperID] = .point(sketchPoint(x: frame.point.x, y: frame.point.y))
        sketch.constraints.append(.fixed(helper))
        try pointPropagator.satisfyAddingConstraint(.coincident(helper, targetPoint.reference), in: &sketch, owner: owner)
        sketch.constraints.removeAll { $0 == .fixed(helper) || $0 == .coincident(helper, targetPoint.reference) }
        sketch.entities[helperID] = nil
        if options.continuity != .g0 {
            try alignEnd(targetPoint, to: frame, continuity: options.continuity, handleDistance: options.targetContinuityDistance, in: &sketch, pointPropagator: pointPropagator)
        }
        var feature = targetPoint.feature
        try commitSketchEntityEdit(featureID: targetPoint.featureID, feature: &feature, sketch: sketch, objectRegistry: objectRegistry, errorOwner: owner)
    }

    /// Gives the target end the reference's tangent (G1) and curvature (G2) at `frame`, once: a
    /// spline's handle along the tangent and, for G2, its next point from the clamped end
    /// conditions; a line turned about the end; an arc re-centred keeping its sweep (and, for G2,
    /// taking the curvature's radius). The target leaves the point the way the reference goes on
    /// past its end, or, inside a curve, the way the target already leaves.
    private func alignEnd(
        _ target: SketchVertexAlignmentPoint,
        to frame: SketchAlignmentFrame,
        continuity: SketchVertexAlignmentContinuity,
        handleDistance: CADExpression?,
        in sketch: inout Sketch,
        pointPropagator: SketchPointConstraintPropagator
    ) throws {
        let owner = "Align Vertex"
        try validateNotGeneratedBridgeCurve(featureID: target.featureID, entityID: target.entityID, operationName: owner)
        guard let endpoint = target.endpoint,
              let current = try SketchCurveEndpointResolver().sample(for: target.reference, sketch: sketch, document: self) else {
            throw unsupportedSketchVertexAlignmentContinuity("G1 and G2 need a target curve end.")
        }
        let point = current.sample.point
        let inward: Point2D
        if let outgoing = frame.outgoing {
            inward = outgoing
        } else {
            let currentInward = Point2D(x: -current.outgoingTangent.x, y: -current.outgoingTangent.y)
            let sign: Double = currentInward.x * frame.tangent.x + currentInward.y * frame.tangent.y >= 0 ? 1 : -1
            inward = Point2D(x: sign * frame.tangent.x, y: sign * frame.tangent.y)
        }
        let k = frame.curvatureVector
        let curvature = hypot(k.x, k.y)
        switch endpoint {
        case .spline(let reference):
            guard case .spline(var spline) = sketch.entities[reference.splineID] else { return }
            let count = spline.controlPoints.count
            let (handle, next) = reference.endpoint == .start ? (1, 2) : (count - 2, count - 3)
            let handlePoint = try resolvedPoint(.splineControlPoint(entity: reference.splineID, index: handle), in: sketch, owner: owner)
            guard let handlePoint else { return }
            let length = try handleDistance.map { try resolvedPositiveLengthValue($0, owner: "\(owner) continuity distance") }
                ?? hypot(handlePoint.x - point.x, handlePoint.y - point.y)
            let p1 = Point2D(x: point.x + inward.x * length, y: point.y + inward.y * length)
            spline.controlPoints[handle] = sketchPoint(x: p1.x, y: p1.y)
            if continuity == .g2 {
                guard spline.degree >= 2, next != handle, next > 0, next < count - 1 else {
                    throw unsupportedSketchVertexAlignmentContinuity("G2 needs a spline of degree 2 or more with room for its curvature point.")
                }
                let scale = try SketchPointConstraintPropagator.SplineEndScale(spline: spline, endpoint: reference.endpoint)
                let firstDerivative = Point2D(x: scale.a * (p1.x - point.x), y: scale.a * (p1.y - point.y))
                let speedSquared = firstDerivative.x * firstDerivative.x + firstDerivative.y * firstDerivative.y
                let second = Point2D(x: speedSquared * k.x, y: speedSquared * k.y)
                let p2 = Point2D(
                    x: p1.x + scale.delta2 * (second.x / scale.b + (p1.x - point.x) / scale.delta1),
                    y: p1.y + scale.delta2 * (second.y / scale.b + (p1.y - point.y) / scale.delta1)
                )
                spline.controlPoints[next] = sketchPoint(x: p2.x, y: p2.y)
            }
            try validateSplineForm(spline, owner: owner)
            sketch.entities[reference.splineID] = .spline(spline)
        case .line(let lineID):
            guard case .line(var line) = sketch.entities[lineID] else { return }
            if continuity == .g2, curvature > 1.0e-9 {
                throw unsupportedSketchVertexAlignmentContinuity("G2 on a line needs a straight reference there.")
            }
            let start = try resolvedSketchPoint(line.start, owner: owner), end = try resolvedSketchPoint(line.end, owner: owner)
            let length = hypot(end.x - start.x, end.y - start.y)
            let far = sketchPoint(x: point.x + inward.x * length, y: point.y + inward.y * length)
            if case .lineStart = target.reference { line.end = far } else { line.start = far }
            sketch.entities[lineID] = .line(line)
        case .circular(let arcID):
            guard case .arc(var arc) = sketch.entities[arcID] else {
                throw unsupportedSketchVertexAlignmentContinuity("G1 and G2 need an arc end.")
            }
            let isStart: Bool
            if case .arcStart = target.reference { isStart = true } else { isStart = false }
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: owner)
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: owner)
            let sweep = positiveArcSpan(startAngle: startAngle, endAngle: endAngle)
            // An arc runs counterclockwise: at its start it travels inward, at its end against it,
            // and its center lies to the left of its travel.
            let travel = isStart ? inward : Point2D(x: -inward.x, y: -inward.y)
            let left = Point2D(x: -travel.y, y: travel.x)
            var radius = try resolvedPositiveLengthValue(arc.radius, owner: owner)
            if continuity == .g2 {
                guard curvature > 1.0e-9, k.x * left.x + k.y * left.y > 0 else {
                    throw unsupportedSketchVertexAlignmentContinuity("G2 on an arc needs the reference to bend the way the arc turns.")
                }
                radius = 1 / curvature
            }
            let center = Point2D(x: point.x + left.x * radius, y: point.y + left.y * radius)
            let angle = atan2(point.y - center.y, point.x - center.x)
            arc.center = sketchPoint(x: center.x, y: center.y)
            arc.radius = .length(radius, .meter)
            arc.startAngle = .angle(isStart ? angle : angle - sweep, .radian)
            arc.endAngle = .angle(isStart ? angle + sweep : angle, .radian)
            sketch.entities[arcID] = .arc(arc)
        }
        try pointPropagator.propagate(from: target.reference, in: &sketch, owner: owner)
    }

    /// The solver treats `.left` as the circle center lying on the positive
    /// cross(direction, center - start) side, so the side is derived from the
    /// currently resolved sketch geometry that the alignment just produced.
    func lineCircularTangencySide(
        lineID: SketchEntityID,
        circularID: SketchEntityID,
        in sketch: Sketch
    ) throws -> SketchTangencyConstraint.LineSide {
        let owner = "Sketch vertex alignment tangency"
        guard case .line(let line)? = sketch.entities[lineID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve the tangent line."
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
                message: "\(owner) could not resolve the tangent circular entity."
            )
        }
        let startX = try resolvedLengthValue(line.start.x, owner: owner)
        let startY = try resolvedLengthValue(line.start.y, owner: owner)
        let endX = try resolvedLengthValue(line.end.x, owner: owner)
        let endY = try resolvedLengthValue(line.end.y, owner: owner)
        let centerX = try resolvedLengthValue(center.x, owner: owner)
        let centerY = try resolvedLengthValue(center.y, owner: owner)
        let cross = (endX - startX) * (centerY - startY) - (endY - startY) * (centerX - startX)
        return cross >= 0.0 ? .left : .right
    }

    /// The solver measures the directed angle between the spline endpoint
    /// tangent (`P1 - P0` at start, `Pn-1 - Pn-2` at end) and the line
    /// direction (`end - start`), so the orientation that preserves the
    /// currently resolved geometry is derived from their dot product.
    public func splineLineTangentOrientation(
        splineID: SketchEntityID,
        endpoint: SketchSplineEndpoint,
        lineID: SketchEntityID,
        in sketch: Sketch
    ) throws -> SketchTangentOrientation {
        let owner = "Spline endpoint tangency"
        guard case .spline(let spline)? = sketch.entities[splineID],
              spline.controlPoints.count >= 2 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve the spline endpoint tangent."
            )
        }
        guard case .line(let line)? = sketch.entities[lineID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) could not resolve the tangent line."
            )
        }
        let tangentStart: SketchPoint
        let tangentEnd: SketchPoint
        switch endpoint {
        case .start:
            tangentStart = spline.controlPoints[0]
            tangentEnd = spline.controlPoints[1]
        case .end:
            tangentStart = spline.controlPoints[spline.controlPoints.count - 2]
            tangentEnd = spline.controlPoints[spline.controlPoints.count - 1]
        }
        let tangentX = try resolvedLengthValue(tangentEnd.x, owner: owner)
            - (try resolvedLengthValue(tangentStart.x, owner: owner))
        let tangentY = try resolvedLengthValue(tangentEnd.y, owner: owner)
            - (try resolvedLengthValue(tangentStart.y, owner: owner))
        let lineX = try resolvedLengthValue(line.end.x, owner: owner)
            - (try resolvedLengthValue(line.start.x, owner: owner))
        let lineY = try resolvedLengthValue(line.end.y, owner: owner)
            - (try resolvedLengthValue(line.start.y, owner: owner))
        let dot = tangentX * lineX + tangentY * lineY
        return dot >= 0.0 ? .aligned : .opposed
    }

    private func unsupportedSketchVertexAlignmentContinuity(_ reason: String) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Align Vertex \(reason)"
        )
    }

    private func sketchAlignmentConstraintExists(
        _ constraint: SketchConstraint,
        in constraints: [SketchConstraint]
    ) -> Bool {
        constraints.contains { existing in
            sketchAlignmentConstraintsMatch(existing, constraint)
        }
    }

    private func sketchAlignmentConstraintsMatch(
        _ first: SketchConstraint,
        _ second: SketchConstraint
    ) -> Bool {
        if first == second {
            return true
        }
        switch (first, second) {
        case (.coincident(let firstA, let firstB), .coincident(let secondA, let secondB)):
            return firstA == secondB && firstB == secondA
        case (.parallel(let firstA, let firstB), .parallel(let secondA, let secondB)),
             (.perpendicular(let firstA, let firstB), .perpendicular(let secondA, let secondB)),
             (.equalLength(let firstA, let firstB), .equalLength(let secondA, let secondB)),
             (.concentric(let firstA, let firstB), .concentric(let secondA, let secondB)),
             (.equalRadius(let firstA, let firstB), .equalRadius(let secondA, let secondB)):
            return firstA == secondB && firstB == secondA
        case (.tangent(let firstTangency), .tangent(let secondTangency)):
            switch (firstTangency, secondTangency) {
            case let (
                .lineCircular(firstLine, firstCircular, _),
                .lineCircular(secondLine, secondCircular, _)
            ):
                return firstLine == secondLine && firstCircular == secondCircular
            case let (
                .circularCircular(firstA, firstB, _),
                .circularCircular(secondA, secondB, _)
            ):
                return firstA == secondB && firstB == secondA
            default:
                return false
            }
        case (.tangentSplineEndpoints(let firstPair), .tangentSplineEndpoints(let secondPair)),
             (.smoothSplineEndpoints(let firstPair), .smoothSplineEndpoints(let secondPair)):
            return firstPair.first == secondPair.second && firstPair.second == secondPair.first
        default:
            return false
        }
    }
}
