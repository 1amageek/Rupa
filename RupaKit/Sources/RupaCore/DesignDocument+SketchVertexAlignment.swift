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
                continuity: options.continuity
            )
            if sketchAlignmentConstraintExists(continuityConstraint, in: sketch.constraints) == false {
                try pointPropagator.satisfyAddingConstraint(
                    continuityConstraint,
                    in: &sketch,
                    owner: "Align Vertex"
                )
            }
        }

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
        if options.targetContinuityDistance != nil || options.referenceContinuityDistance != nil {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex CV continuity distance controls require distance-aware spline handle solving that is not implemented yet."
            )
        }
        if options.showsCurvature {
            throw EditorError(
                code: .commandInvalid,
                message: "Align Vertex Show Curvature requires command-scoped curvature display wiring that is not implemented yet."
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
        continuity: SketchVertexAlignmentContinuity
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
                return .tangent(referenceCircularID, targetLineID)
            case (.circular(let targetCircularID), .line(let referenceLineID)):
                return .tangent(referenceLineID, targetCircularID)
            case (.spline(let targetEndpoint), .line(let referenceLineID)):
                return .splineEndpointTangent(
                    spline: targetEndpoint.splineID,
                    endpoint: targetEndpoint.endpoint,
                    line: referenceLineID
                )
            case (.spline(let targetEndpoint), .spline(let referenceEndpoint)):
                return .tangentSplineEndpoints(
                    first: referenceEndpoint,
                    second: targetEndpoint
                )
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
                return .smoothSplineEndpoints(
                    first: referenceEndpoint,
                    second: targetEndpoint
                )
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
             (.tangent(let firstA, let firstB), .tangent(let secondA, let secondB)),
             (.concentric(let firstA, let firstB), .concentric(let secondA, let secondB)),
             (.equalRadius(let firstA, let firstB), .equalRadius(let secondA, let secondB)):
            return firstA == secondB && firstB == secondA
        case (.tangentSplineEndpoints(let firstA, let firstB), .tangentSplineEndpoints(let secondA, let secondB)),
             (.smoothSplineEndpoints(let firstA, let firstB), .smoothSplineEndpoints(let secondA, let secondB)):
            return firstA == secondB && firstB == secondA
        default:
            return false
        }
    }
}
