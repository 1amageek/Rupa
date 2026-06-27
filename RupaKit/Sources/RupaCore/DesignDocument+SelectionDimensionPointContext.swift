import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func isSourcePointAnchored(
        _ context: SelectionDimensionSourcePointContext
    ) throws -> Bool {
        guard let feature = cadDocument.designGraph.nodes[context.featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing source sketch feature."
            )
        }
        let reference = try sketchReference(for: context)
        return SketchPointConstraintPropagator(parameters: cadDocument.parameters)
            .isAnchored(reference, in: sketch)
    }

    func sketchReference(
        for context: SelectionDimensionSourcePointContext
    ) throws -> SketchReference {
        switch context.role {
        case .handle(let handle):
            switch handle {
            case .point:
                return .entity(context.entityID)
            case .lineStart:
                return .lineStart(context.entityID)
            case .lineEnd:
                return .lineEnd(context.entityID)
            case .circleCenter:
                return .circleCenter(context.entityID)
            case .arcCenter:
                return .arcCenter(context.entityID)
            case .arcStart:
                return .arcStart(context.entityID)
            case .arcEnd:
                return .arcEnd(context.entityID)
            }
        case .splineControlPoint(let index):
            return .splineControlPoint(entity: context.entityID, index: index)
        }
    }

    func sourcePointContext(
        reference: SelectionReference
    ) throws -> SelectionDimensionSourcePointContext {
        switch reference {
        case .curve(let curveReference):
            switch curveReference {
            case .parameter(let parameter):
                return try sourceParameterPointContext(parameter)
            case .center(let center):
                return try sourceCenterPointContext(center)
            case .controlPoint(let controlPoint):
                return try sourceControlPointContext(controlPoint)
            case .whole, .span, .knot:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point distance application requires line endpoint, circle center, arc center, arc endpoint, spline control point, or standalone sketch point references."
                )
            }
        case .sketchPoint(let point):
            return try sourceStandalonePointContext(point)
        case .topology, .edge, .surface:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application requires source sketch point references."
            )
        }
    }

    func sourceParameterPointContext(
        _ parameter: CurveParameterReference
    ) throws -> SelectionDimensionSourcePointContext {
        let featureID = parameter.curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: parameter.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing source sketch entity."
            )
        }

        let handle: SketchEntityPointHandle
        switch entity {
        case .line:
            let lineLength = try sourceLineLength(featureID: featureID, entityID: entityID)
            switch try lineEndpointRole(parameter: parameter.parameter, lineLength: lineLength) {
            case .start:
                handle = .lineStart
            case .end:
                handle = .lineEnd
            }
        case .arc:
            let endpointParameters = try sourceArcEndpointParameters(featureID: featureID, entityID: entityID)
            switch try arcEndpointRole(parameter: parameter.parameter, endpointParameters: endpointParameters) {
            case .start:
                handle = .arcStart
            case .end:
                handle = .arcEnd
            }
        case .point, .circle, .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application parameter references currently support source line endpoints and source arc endpoints only."
            )
        }

        return SelectionDimensionSourcePointContext(
            featureID: featureID,
            entityID: entityID,
            curve: parameter.curve,
            plane: sketch.plane,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID),
            role: .handle(handle)
        )
    }

    func sourceCenterPointContext(
        _ center: CurveCenterReference
    ) throws -> SelectionDimensionSourcePointContext {
        let featureID = center.curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: center.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing source circular entity."
            )
        }

        let handle: SketchEntityPointHandle
        switch entity {
        case .circle:
            handle = .circleCenter
        case .arc:
            handle = .arcCenter
        case .point, .line, .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application center references currently support source circle and arc centers only."
            )
        }

        return SelectionDimensionSourcePointContext(
            featureID: featureID,
            entityID: entityID,
            curve: center.curve,
            plane: sketch.plane,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID),
            role: .handle(handle)
        )
    }

    func sourceControlPointContext(
        _ controlPoint: CurveControlPointReference
    ) throws -> SelectionDimensionSourcePointContext {
        let featureID = controlPoint.curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: controlPoint.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case let .spline(spline) = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing source spline control point."
            )
        }
        guard spline.controlPoints.indices.contains(controlPoint.controlPointIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing source spline control point index."
            )
        }

        return SelectionDimensionSourcePointContext(
            featureID: featureID,
            entityID: entityID,
            curve: controlPoint.curve,
            plane: sketch.plane,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID),
            role: .splineControlPoint(controlPoint.controlPointIndex)
        )
    }

    func sourceStandalonePointContext(
        _ point: SketchPointSelectionReference
    ) throws -> SelectionDimensionSourcePointContext {
        guard let feature = cadDocument.designGraph.nodes[point.featureID],
              case let .sketch(sketch) = feature.operation,
              case .point = sketch.entities[point.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing standalone source sketch point."
            )
        }

        return SelectionDimensionSourcePointContext(
            featureID: point.featureID,
            entityID: point.entityID,
            curve: nil,
            plane: sketch.plane,
            target: try sourceSketchEntityTarget(featureID: point.featureID, entityID: point.entityID),
            role: .handle(.point)
        )
    }
}
