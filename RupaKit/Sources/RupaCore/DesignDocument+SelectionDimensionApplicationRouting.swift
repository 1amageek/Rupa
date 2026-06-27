import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func sourceSelectionDimensionApplication(
        for dimension: SelectionDimension,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SelectionDimensionSourceApplication {
        switch dimension.kind {
        case .distance:
            if let objectFaceContext = try sourceObjectFaceDistanceDimensionContextIfPresent(
                for: dimension,
                objectRegistry: objectRegistry
            ) {
                return .objectFaceDistance(objectFaceContext)
            }
            if let pointLineContext = try sourcePointLineDistanceDimensionContextIfPresent(for: dimension) {
                return .sourcePointLineDistance(pointLineContext)
            }
            switch (dimension.first, dimension.second) {
            case (.curve(.parameter(let firstParameter)), .curve(.parameter(let secondParameter))):
                if try isSourceLineParameterPair(firstParameter, secondParameter) {
                    return .lineLength(try sourceLineEndpointDimensionContext(for: dimension))
                }
                return .sourcePointDistance(try sourcePointDistanceDimensionContext(for: dimension))
            case (.curve(.center(let center)), .curve(let radialReference)):
                if try isSourceCircularRadiusDistance(center: center, radialReference: radialReference) {
                    return .circularRadius(try sourceCircularRadiusDimensionContext(
                        center: center,
                        radialReference: radialReference
                    ))
                }
                return .sourcePointDistance(try sourcePointDistanceDimensionContext(for: dimension))
            case (.curve(let radialReference), .curve(.center(let center))):
                if try isSourceCircularRadiusDistance(center: center, radialReference: radialReference) {
                    return .circularRadius(try sourceCircularRadiusDimensionContext(
                        center: center,
                        radialReference: radialReference
                    ))
                }
                return .sourcePointDistance(try sourcePointDistanceDimensionContext(for: dimension))
            case (.curve(.controlPoint), .curve),
                 (.curve, .curve(.controlPoint)):
                return .sourcePointDistance(try sourcePointDistanceDimensionContext(for: dimension))
            case (.sketchPoint, .curve),
                 (.curve, .sketchPoint),
                 (.sketchPoint, .sketchPoint):
                return .sourcePointDistance(try sourcePointDistanceDimensionContext(for: dimension))
            default:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection dimension application currently supports source line length, source circle/arc radius, source sketch point-to-point distance, source spline control-point distance, source point-line distance, and supported object face-distance dimensions."
                )
            }
        case .angle:
            switch (dimension.first, dimension.second) {
            case (.curve(.parameter(let firstParameter)), .curve(.parameter(let secondParameter))):
                if try isSourceArcParameterPair(firstParameter, secondParameter) {
                    return .arcSpanAngle(try sourceArcSpanAngleDimensionContext(for: dimension))
                }
                return .lineRelativeAngle(try sourceLineAngleDimensionContext(
                    firstReference: .parameter(firstParameter),
                    secondReference: .parameter(secondParameter)
                ))
            case (.curve(let firstReference), .curve(let secondReference)):
                return .lineRelativeAngle(try sourceLineAngleDimensionContext(
                    firstReference: firstReference,
                    secondReference: secondReference
                ))
            default:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection dimension application currently supports source line relative angle and source arc span angle dimensions."
                )
            }
        }
    }

    func sourceLineEndpointDimensionContext(
        for dimension: SelectionDimension
    ) throws -> SelectionDimensionSourceLineContext {
        guard case .curve(.parameter(let firstParameter)) = dimension.first,
              case .curve(.parameter(let secondParameter)) = dimension.second else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application currently supports source line endpoint parameters only."
            )
        }
        guard firstParameter.curve == secondParameter.curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires both references to belong to the same source curve."
            )
        }

        let featureID = firstParameter.curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: firstParameter.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case .line = sketch.entities[entityID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application currently supports source line endpoint dimensions only."
            )
        }

        let lineLength = try sourceLineLength(
            featureID: featureID,
            entityID: entityID
        )
        let firstRole = try lineEndpointRole(
            parameter: firstParameter.parameter,
            lineLength: lineLength
        )
        let secondRole = try lineEndpointRole(
            parameter: secondParameter.parameter,
            lineLength: lineLength
        )
        guard firstRole != secondRole else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires one line start reference and one line end reference."
            )
        }

        return SelectionDimensionSourceLineContext(
            featureID: featureID,
            entityID: entityID,
            curve: firstParameter.curve,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID),
            firstRole: firstRole,
            secondRole: secondRole
        )
    }

    func sourceCircularRadiusDimensionContext(
        center: CurveCenterReference,
        radialReference: CurveSubobjectReference
    ) throws -> SelectionDimensionSourceCircularContext {
        let radialCurve = try radialCurveOutputReference(from: radialReference)
        guard center.curve == radialCurve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires the center and radial reference to belong to the same source curve."
            )
        }

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
                message: "Selection dimension application requires an existing source circular entity."
            )
        }
        switch entity {
        case .circle, .arc:
            break
        case .point, .line, .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application currently supports source circle and arc radius dimensions only."
            )
        }

        return SelectionDimensionSourceCircularContext(
            featureID: featureID,
            entityID: entityID,
            curve: center.curve,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID)
        )
    }

    func sourceLineAngleDimensionContext(
        firstReference: CurveSubobjectReference,
        secondReference: CurveSubobjectReference
    ) throws -> SelectionDimensionSourceLineAngleContext {
        let firstCurve = try angleCurveOutputReference(from: firstReference)
        let secondCurve = try angleCurveOutputReference(from: secondReference)
        guard firstCurve != secondCurve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection angle application requires two different source line references."
            )
        }

        let firstLine = try sourceLineAngleContext(curve: firstCurve)
        let referenceLine = try sourceLineAngleContext(curve: secondCurve)
        guard firstLine.plane == referenceLine.plane else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection line angle application requires both source lines to share the same sketch plane."
            )
        }

        return SelectionDimensionSourceLineAngleContext(
            featureID: firstLine.featureID,
            entityID: firstLine.entityID,
            curve: firstCurve,
            target: firstLine.target,
            currentAngle: firstLine.angle,
            referenceAngle: referenceLine.angle
        )
    }

    func sourceArcSpanAngleDimensionContext(
        for dimension: SelectionDimension
    ) throws -> SelectionDimensionSourceArcAngleContext {
        guard case .curve(.parameter(let firstParameter)) = dimension.first,
              case .curve(.parameter(let secondParameter)) = dimension.second else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc span application requires source arc endpoint parameters."
            )
        }
        guard firstParameter.curve == secondParameter.curve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc span application requires both references to belong to the same source arc."
            )
        }

        let featureID = firstParameter.curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: firstParameter.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case .arc = sketch.entities[entityID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc span application currently supports source arc endpoint parameters only."
            )
        }

        let endpointParameters = try sourceArcEndpointParameters(
            featureID: featureID,
            entityID: entityID
        )
        let firstRole = try arcEndpointRole(
            parameter: firstParameter.parameter,
            endpointParameters: endpointParameters
        )
        let secondRole = try arcEndpointRole(
            parameter: secondParameter.parameter,
            endpointParameters: endpointParameters
        )
        guard firstRole != secondRole else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc span application requires one arc start reference and one arc end reference."
            )
        }

        return SelectionDimensionSourceArcAngleContext(
            featureID: featureID,
            entityID: entityID,
            curve: firstParameter.curve,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID),
            firstRole: firstRole,
            secondRole: secondRole
        )
    }

    func sourcePointLineDistanceDimensionContextIfPresent(
        for dimension: SelectionDimension
    ) throws -> SelectionDimensionSourcePointLineDistanceContext? {
        switch (dimension.first, dimension.second) {
        case (.curve(.whole(let lineCurve)), let pointReference):
            guard try isSourceLineWholeCurve(lineCurve) else {
                return nil
            }
            return try sourcePointLineDistanceDimensionContext(
                pointReference: pointReference,
                lineCurve: lineCurve,
                pointIsFirst: false
            )
        case (let pointReference, .curve(.whole(let lineCurve))):
            guard try isSourceLineWholeCurve(lineCurve) else {
                return nil
            }
            return try sourcePointLineDistanceDimensionContext(
                pointReference: pointReference,
                lineCurve: lineCurve,
                pointIsFirst: true
            )
        default:
            return nil
        }
    }

    func sourcePointLineDistanceDimensionContext(
        pointReference: SelectionReference,
        lineCurve: CurveOutputReference,
        pointIsFirst: Bool
    ) throws -> SelectionDimensionSourcePointLineDistanceContext {
        let point = try sourcePointContext(reference: pointReference)
        guard isArcEndpointRole(point.role) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application currently does not support source arc endpoint points."
            )
        }
        let line = try sourceLineDistanceContext(curve: lineCurve)
        guard point.plane == line.plane else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application requires the source point and line to share the same sketch plane."
            )
        }
        guard point.featureID != line.featureID || point.entityID != line.entityID else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application requires the source point to be separate from the measured source line."
            )
        }
        return SelectionDimensionSourcePointLineDistanceContext(
            point: point,
            line: line,
            pointIsFirst: pointIsFirst
        )
    }

    func sourcePointDistanceDimensionContext(
        for dimension: SelectionDimension
    ) throws -> SelectionDimensionSourcePointDistanceContext {
        let first = try sourcePointContext(
            reference: dimension.first
        )
        let second = try sourcePointContext(
            reference: dimension.second
        )
        guard first.plane == second.plane else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application requires both source points to share the same sketch plane."
            )
        }
        guard first.featureID != second.featureID ||
            first.entityID != second.entityID ||
            first.role != second.role else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application requires two distinct source point handles."
            )
        }
        return SelectionDimensionSourcePointDistanceContext(first: first, second: second)
    }

    func sourcePointDistanceMovePlan(
        for context: SelectionDimensionSourcePointDistanceContext
    ) throws -> SelectionDimensionSourcePointMovePlan {
        if try isSourcePointAnchored(context.first) == false {
            return SelectionDimensionSourcePointMovePlan(
                moving: context.first,
                anchor: context.second
            )
        }
        if try isSourcePointAnchored(context.second) == false {
            return SelectionDimensionSourcePointMovePlan(
                moving: context.second,
                anchor: context.first
            )
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Selection point distance application requires at least one non-fixed source point."
        )
    }
}
