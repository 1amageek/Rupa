import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
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

        if options.continuity != .g0 {
            let continuityConstraint = try sketchVertexAlignmentContinuityConstraint(
                target: targetPoint,
                reference: referencePoint,
                continuity: options.continuity,
                sketch: sketch
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
        if options.referenceParameter != nil {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex reference parameter support requires curve-parameter source targeting that is not implemented yet."
            )
        }
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

    private func sketchVertexAlignmentContinuityConstraint(
        target: SketchVertexAlignmentPoint,
        reference: SketchVertexAlignmentPoint,
        continuity: SketchVertexAlignmentContinuity,
        sketch: Sketch
    ) throws -> SketchConstraint {
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
                return .tangent(try lineCircularTangency(
                    lineID: targetLineID,
                    circularID: referenceCircularID,
                    sketch: sketch
                ))
            case (.circular(let targetCircularID), .line(let referenceLineID)):
                return .tangent(try lineCircularTangency(
                    lineID: referenceLineID,
                    circularID: targetCircularID,
                    sketch: sketch
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
                    orientation: .aligned
                ))
            case (.line, .spline),
                 (.circular, .circular),
                 (.circular, .spline),
                 (.spline, .circular):
                throw unsupportedSketchVertexAlignmentContinuity(
                    "G1 continuity currently supports target line to reference line or arc, target arc to reference line, target spline endpoint to reference line, and target spline endpoint to reference spline endpoint."
                )
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
                    orientation: .aligned
                ))
            case (.line, _),
                 (.circular, _),
                 (.spline, .line),
                 (.spline, .circular):
                throw unsupportedSketchVertexAlignmentContinuity(
                    "G2 continuity currently requires target and reference spline endpoints."
                )
            }
        }
    }

    private func lineCircularTangency(
        lineID: SketchEntityID,
        circularID: SketchEntityID,
        sketch: Sketch
    ) throws -> SketchTangencyConstraint {
        guard case .line(let line) = sketch.entities[lineID] else {
            throw unsupportedSketchVertexAlignmentContinuity(
                "G1 continuity requires an existing line entity."
            )
        }
        let center: SketchPoint
        switch sketch.entities[circularID] {
        case .circle(let circle):
            center = circle.center
        case .arc(let arc):
            center = arc.center
        default:
            throw unsupportedSketchVertexAlignmentContinuity(
                "G1 continuity requires an existing circular entity."
            )
        }
        let startX = try resolvedLengthValue(line.start.x, owner: "Align Vertex line start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "Align Vertex line start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "Align Vertex line end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "Align Vertex line end y")
        let centerX = try resolvedLengthValue(center.x, owner: "Align Vertex circular center x")
        let centerY = try resolvedLengthValue(center.y, owner: "Align Vertex circular center y")
        let cross = (endX - startX) * (centerY - startY) -
            (endY - startY) * (centerX - startX)
        let side: SketchTangencyConstraint.LineSide = cross >= 0.0 ? .left : .right
        return .lineCircular(line: lineID, circular: circularID, side: side)
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
        case (.tangent(let first), .tangent(let second)):
            return first == second
        case (.tangentSplineEndpoints(let first), .tangentSplineEndpoints(let second)),
             (.smoothSplineEndpoints(let first), .smoothSplineEndpoints(let second)):
            return first.orientation == second.orientation &&
                first.first == second.second && first.second == second.first
        default:
            return false
        }
    }
}
