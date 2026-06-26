import Foundation
import SwiftCAD

public extension DesignDocument {
    @discardableResult
    mutating func addSelectionDimension(
        name: String? = nil,
        kind: SelectionDimensionKind,
        first: SelectionTarget,
        second: SelectionTarget,
        target: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimensionID {
        let resolver = SelectionDimensionTargetResolver()
        let firstReference = try resolver.reference(
            for: first,
            in: self,
            objectRegistry: objectRegistry
        )
        let secondReference = try resolver.reference(
            for: second,
            in: self,
            objectRegistry: objectRegistry
        )
        var updatedCADDocument = cadDocument
        let dimensionID: SelectionDimensionID
        do {
            dimensionID = try updatedCADDocument.addSelectionDimension(
                name: normalizedSelectionDimensionName(name),
                kind: kind,
                first: firstReference,
                second: secondReference,
                target: target
            )
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension produced an invalid CAD document: \(String(describing: error))"
            )
        }
        cadDocument = updatedCADDocument
        return dimensionID
    }

    @discardableResult
    mutating func setSelectionDimensionTarget(
        id: SelectionDimensionID,
        target: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimension {
        guard cadDocument.selectionDimensions.contains(where: { $0.id == id }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension target update requires an existing selection dimension."
            )
        }

        var updatedCADDocument = cadDocument
        let updatedDimension: SelectionDimension
        do {
            updatedDimension = try updatedCADDocument.setSelectionDimensionTarget(
                id: id,
                target: target
            )
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension target update produced an invalid CAD document: \(String(describing: error))"
            )
        }

        var updatedDocument = self
        updatedDocument.cadDocument = updatedCADDocument
        try updatedDocument.productMetadata.validate(
            against: updatedDocument.cadDocument,
            objectRegistry: objectRegistry
        )
        self = updatedDocument
        return updatedDimension
    }

    @discardableResult
    mutating func applySelectionDimensionTarget(
        id: SelectionDimensionID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimension {
        let originalDocument = self
        do {
            guard let dimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Selection dimension application requires an existing selection dimension."
                )
            }

            let dimension = cadDocument.selectionDimensions[dimensionIndex]
            let application = try sourceSelectionDimensionApplication(for: dimension)
            switch application {
            case .lineLength(let context):
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .length,
                    value: dimension.target,
                    objectRegistry: objectRegistry
                )

                let updatedLength = try sourceLineLength(
                    featureID: context.featureID,
                    entityID: context.entityID
                )
                let updatedFirst = selectionReference(
                    curve: context.curve,
                    role: context.firstRole,
                    lineLength: updatedLength
                )
                let updatedSecond = selectionReference(
                    curve: context.curve,
                    role: context.secondRole,
                    lineLength: updatedLength
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                cadDocument.selectionDimensions[updatedDimensionIndex].first = updatedFirst
                cadDocument.selectionDimensions[updatedDimensionIndex].second = updatedSecond
                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .circularRadius(let context):
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .radius,
                    value: dimension.target,
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .lineRelativeAngle(let context):
                let targetAngle = try resolvedAngle(
                    dimension.target,
                    owner: "Selection dimension application target angle"
                )
                let appliedAngle = lineAngleClosestToCurrent(
                    referenceAngle: context.referenceAngle,
                    targetAngle: targetAngle,
                    currentAngle: context.currentAngle
                )
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .angle,
                    value: .angle(appliedAngle, .radian),
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .arcSpanAngle(let context):
                try setSketchEntityDimension(
                    target: context.target,
                    kind: .angle,
                    value: dimension.target,
                    objectRegistry: objectRegistry
                )
                let updatedParameters = try sourceArcEndpointParameters(
                    featureID: context.featureID,
                    entityID: context.entityID
                )
                let updatedFirst = selectionReference(
                    curve: context.curve,
                    role: context.firstRole,
                    arcEndpointParameters: updatedParameters
                )
                let updatedSecond = selectionReference(
                    curve: context.curve,
                    role: context.secondRole,
                    arcEndpointParameters: updatedParameters
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                cadDocument.selectionDimensions[updatedDimensionIndex].first = updatedFirst
                cadDocument.selectionDimensions[updatedDimensionIndex].second = updatedSecond
                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            case .sourcePointDistance(let context):
                try applySourcePointDistanceDimension(
                    id: id,
                    dimension: dimension,
                    context: context,
                    objectRegistry: objectRegistry
                )
                guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Selection dimension application lost the source selection dimension."
                    )
                }

                try cadDocument.validate()
                try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
                return cadDocument.selectionDimensions[updatedDimensionIndex]
            }
        } catch let error as EditorError {
            self = originalDocument
            throw error
        } catch {
            self = originalDocument
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application produced an invalid document state: \(String(describing: error))"
            )
        }
    }

    @discardableResult
    mutating func removeSelectionDimension(
        id: SelectionDimensionID,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SelectionDimension {
        guard cadDocument.selectionDimensions.contains(where: { $0.id == id }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension removal requires an existing selection dimension."
            )
        }

        var updatedCADDocument = cadDocument
        let removedDimension: SelectionDimension
        do {
            removedDimension = try updatedCADDocument.removeSelectionDimension(id: id)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension removal produced an invalid CAD document: \(String(describing: error))"
            )
        }

        var updatedDocument = self
        updatedDocument.cadDocument = updatedCADDocument
        try updatedDocument.productMetadata.validate(
            against: updatedDocument.cadDocument,
            objectRegistry: objectRegistry
        )
        self = updatedDocument
        return removedDimension
    }

    private func normalizedSelectionDimensionName(_ name: String?) -> String? {
        guard let name else {
            return nil
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private func sourceSelectionDimensionApplication(
        for dimension: SelectionDimension
    ) throws -> SelectionDimensionSourceApplication {
        switch dimension.kind {
        case .distance:
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
            default:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection dimension application currently supports source line length, source circle/arc radius, source sketch point-to-point distance, and source spline control-point distance dimensions."
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

    private mutating func applySourcePointDistanceDimension(
        id: SelectionDimensionID,
        dimension: SelectionDimension,
        context: SelectionDimensionSourcePointDistanceContext,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let targetDistance = try resolvedLength(
            dimension.target,
            owner: "Selection point distance application target"
        )
        guard targetDistance >= 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application target must not be negative."
            )
        }

        if isArcEndpointRole(context.first.role) {
            try applySourceArcEndpointPointDistanceDimension(
                id: id,
                targetDistance: targetDistance,
                context: context,
                objectRegistry: objectRegistry
            )
            return
        }

        let firstPoint = try sourcePoint(context.first)
        let secondPoint = try sourcePoint(context.second)
        let currentDeltaX = firstPoint.x - secondPoint.x
        let currentDeltaY = firstPoint.y - secondPoint.y
        let currentDistance = hypot(currentDeltaX, currentDeltaY)
        if currentDistance <= selectionDimensionEndpointTolerance {
            guard targetDistance <= selectionDimensionEndpointTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point distance application requires a non-zero current point distance to preserve direction."
                )
            }
            try refreshSourcePointDistanceReferences(id: id, context: context)
            return
        }

        let scale = targetDistance / currentDistance
        let targetPoint = Point2D(
            x: secondPoint.x + currentDeltaX * scale,
            y: secondPoint.y + currentDeltaY * scale
        )
        let deltaX = targetPoint.x - firstPoint.x
        let deltaY = targetPoint.y - firstPoint.y
        guard deltaX.isFinite, deltaY.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application produced a non-finite movement delta."
            )
        }

        if abs(deltaX) > selectionDimensionEndpointTolerance ||
            abs(deltaY) > selectionDimensionEndpointTolerance {
            try moveSourcePoint(
                context.first,
                deltaX: .length(deltaX, .meter),
                deltaY: .length(deltaY, .meter),
                objectRegistry: objectRegistry
            )
        }
        try refreshSourcePointDistanceReferences(id: id, context: context)
    }

    private mutating func refreshSourcePointDistanceReferences(
        id: SelectionDimensionID,
        context: SelectionDimensionSourcePointDistanceContext
    ) throws {
        guard let updatedDimensionIndex = cadDocument.selectionDimensions.firstIndex(where: { $0.id == id }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application lost the source selection dimension."
            )
        }
        cadDocument.selectionDimensions[updatedDimensionIndex].first = try selectionReference(point: context.first)
        cadDocument.selectionDimensions[updatedDimensionIndex].second = try selectionReference(point: context.second)
    }

    private mutating func applySourceArcEndpointPointDistanceDimension(
        id: SelectionDimensionID,
        targetDistance: Double,
        context: SelectionDimensionSourcePointDistanceContext,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let arc = try sourceArc(
            for: context.first,
            owner: "Selection arc endpoint distance application"
        )
        let center = try resolvedPoint(
            arc.center,
            owner: "Selection arc endpoint distance application center"
        )
        let radius = try resolvedLength(
            arc.radius,
            owner: "Selection arc endpoint distance application radius"
        )
        let endpointRole: SelectionDimensionCurveEndpointRole
        switch context.first.role {
        case .handle(.arcStart):
            endpointRole = .start
        case .handle(.arcEnd):
            endpointRole = .end
        case .handle(.point),
             .handle(.lineStart),
             .handle(.lineEnd),
             .handle(.circleCenter),
             .handle(.arcCenter),
             .splineControlPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance application requires an arc endpoint as the moving source point."
            )
        }
        let currentPoint = try sourceArcEndpointPoint(
            arc,
            endpoint: endpointRole,
            owner: "Selection arc endpoint distance application current endpoint"
        )
        let anchorPoint = try sourcePoint(context.second)
        let targetPoint = try sourceArcEndpointTargetPoint(
            center: center,
            radius: radius,
            anchor: anchorPoint,
            targetDistance: targetDistance,
            currentPoint: currentPoint
        )
        let deltaX = targetPoint.x - currentPoint.x
        let deltaY = targetPoint.y - currentPoint.y
        guard deltaX.isFinite, deltaY.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance application produced a non-finite movement delta."
            )
        }

        if abs(deltaX) > selectionDimensionEndpointTolerance ||
            abs(deltaY) > selectionDimensionEndpointTolerance {
            try moveSourcePoint(
                context.first,
                deltaX: .length(deltaX, .meter),
                deltaY: .length(deltaY, .meter),
                objectRegistry: objectRegistry
            )
        }
        try refreshSourcePointDistanceReferences(id: id, context: context)
    }

    private func sourceLineEndpointDimensionContext(
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

    private func sourceCircularRadiusDimensionContext(
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

    private func sourceLineAngleDimensionContext(
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

    private func sourceArcSpanAngleDimensionContext(
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

    private func sourcePointDistanceDimensionContext(
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

    private func sourcePointContext(
        reference: SelectionReference
    ) throws -> SelectionDimensionSourcePointContext {
        guard case .curve(let curveReference) = reference else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application requires source sketch point curve references."
            )
        }
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
                message: "Selection point distance application requires line endpoint, circle center, arc center, arc endpoint, or spline control point references."
            )
        }
    }

    private func sourceParameterPointContext(
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

    private func sourceCenterPointContext(
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

    private func sourceControlPointContext(
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

    private func isSourceArcParameterPair(
        _ first: CurveParameterReference,
        _ second: CurveParameterReference
    ) throws -> Bool {
        guard first.curve == second.curve else {
            return false
        }
        let entityID = try sourceCurveEntityID(
            featureID: first.curve.featureID,
            curveIndex: first.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[first.curve.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection angle application could not resolve the source curve entity."
            )
        }
        if case .arc = entity {
            return true
        }
        return false
    }

    private func isSourceLineParameterPair(
        _ first: CurveParameterReference,
        _ second: CurveParameterReference
    ) throws -> Bool {
        guard first.curve == second.curve else {
            return false
        }
        let entityID = try sourceCurveEntityID(
            featureID: first.curve.featureID,
            curveIndex: first.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[first.curve.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection distance application could not resolve the source curve entity."
            )
        }
        if case .line = entity {
            return true
        }
        return false
    }

    private func isSourceCircularRadiusDistance(
        center: CurveCenterReference,
        radialReference: CurveSubobjectReference
    ) throws -> Bool {
        let radialCurve: CurveOutputReference
        switch radialReference {
        case .whole(let curve):
            radialCurve = curve
        case .parameter(let parameter):
            radialCurve = parameter.curve
        case .span(let span):
            radialCurve = span.curve
        case .center, .controlPoint, .knot:
            return false
        }
        guard center.curve == radialCurve else {
            return false
        }
        let entityID = try sourceCurveEntityID(
            featureID: center.curve.featureID,
            curveIndex: center.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[center.curve.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection radius application could not resolve the source curve entity."
            )
        }
        switch entity {
        case .circle, .arc:
            return true
        case .point, .line, .spline:
            return false
        }
    }

    private func radialCurveOutputReference(
        from reference: CurveSubobjectReference
    ) throws -> CurveOutputReference {
        switch reference {
        case .whole(let curve):
            return curve
        case .parameter(let parameter):
            return parameter.curve
        case .span(let span):
            return span.curve
        case .center, .controlPoint, .knot:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires a radial curve point or whole curve reference."
            )
        }
    }

    private func angleCurveOutputReference(
        from reference: CurveSubobjectReference
    ) throws -> CurveOutputReference {
        switch reference {
        case .whole(let curve):
            return curve
        case .parameter(let parameter):
            return parameter.curve
        case .span(let span):
            return span.curve
        case .center, .controlPoint, .knot:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection angle application requires source curve references with tangent direction."
            )
        }
    }

    private func sourceCurveEntityID(
        featureID: FeatureID,
        curveIndex: Int
    ) throws -> SketchEntityID {
        guard curveIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires a non-negative source curve index."
            )
        }
        let curveEntityIDs = try sourceCurveEntityIDs(featureID: featureID)
        guard curveIndex < curveEntityIDs.count else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application could not resolve the source curve index."
            )
        }
        return curveEntityIDs[curveIndex]
    }

    private func sourceCurveEntityIDs(
        featureID: FeatureID
    ) throws -> [SketchEntityID] {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application requires a source sketch feature."
            )
        }
        return sketch.entities
            .sorted(by: { $0.key.description < $1.key.description })
            .compactMap { entityID, entity in
                if case .point = entity {
                    return nil
                }
                return entityID
            }
    }

    private func sketchSceneNodeID(
        featureID: FeatureID
    ) throws -> SceneNodeID {
        guard let sceneNodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.reference == .sketch(featureID)
        })?.key else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application could not resolve the source sketch scene node."
            )
        }
        return sceneNodeID
    }

    private func sourceSketchEntityTarget(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> SelectionTarget {
        SelectionTarget(
            sceneNodeID: try sketchSceneNodeID(featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: featureID,
                    entityID: entityID
                )
            )
        )
    }

    private func sourceLineLength(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> Double {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case let .line(line) = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application requires an existing source line."
            )
        }
        let start = try resolvedPoint(line.start, owner: "Selection dimension application line start")
        let end = try resolvedPoint(line.end, owner: "Selection dimension application line end")
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func sourceLineAngleContext(
        curve: CurveOutputReference
    ) throws -> SourceLineAngleContext {
        let featureID = curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case let .line(line) = sketch.entities[entityID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection line angle application currently supports source line references only."
            )
        }
        let start = try resolvedPoint(line.start, owner: "Selection line angle application line start")
        let end = try resolvedPoint(line.end, owner: "Selection line angle application line end")
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx.isFinite, dy.isFinite, hypot(dx, dy) > selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection line angle application requires non-degenerate source lines."
            )
        }
        return SourceLineAngleContext(
            featureID: featureID,
            entityID: entityID,
            plane: sketch.plane,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID),
            angle: atan2(dy, dx)
        )
    }

    private func sourcePoint(
        _ context: SelectionDimensionSourcePointContext
    ) throws -> Point2D {
        guard let feature = cadDocument.designGraph.nodes[context.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[context.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point distance application requires an existing source sketch point."
            )
        }
        switch context.role {
        case .handle(let handle):
            switch (handle, entity) {
            case (.lineStart, .line(let line)):
                return try resolvedPoint(line.start, owner: "Selection point distance line start")
            case (.lineEnd, .line(let line)):
                return try resolvedPoint(line.end, owner: "Selection point distance line end")
            case (.circleCenter, .circle(let circle)):
                return try resolvedPoint(circle.center, owner: "Selection point distance circle center")
            case (.arcCenter, .arc(let arc)):
                return try resolvedPoint(arc.center, owner: "Selection point distance arc center")
            case (.arcStart, .arc(let arc)):
                return try sourceArcEndpointPoint(
                    arc,
                    endpoint: .start,
                    owner: "Selection point distance arc start"
                )
            case (.arcEnd, .arc(let arc)):
                return try sourceArcEndpointPoint(
                    arc,
                    endpoint: .end,
                    owner: "Selection point distance arc end"
                )
            case (.point, .point(let point)):
                return try resolvedPoint(point, owner: "Selection point distance point")
            default:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point distance application source point handle no longer matches the source entity."
                )
            }
        case .splineControlPoint(let index):
            guard case .spline(let spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection point distance application source spline control point no longer matches the source entity."
                )
            }
            return try resolvedPoint(
                spline.controlPoints[index],
                owner: "Selection point distance spline control point"
            )
        }
    }

    private mutating func moveSourcePoint(
        _ context: SelectionDimensionSourcePointContext,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        switch context.role {
        case .handle(let handle):
            try moveSketchEntityPoint(
                target: context.target,
                handle: handle,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            )
        case .splineControlPoint(let index):
            try moveSketchSplineControlPoint(
                target: context.target,
                controlPointIndex: index,
                deltaX: deltaX,
                deltaY: deltaY,
                objectRegistry: objectRegistry
            )
        }
    }

    private func sourceArc(
        for context: SelectionDimensionSourcePointContext,
        owner: String
    ) throws -> SketchArc {
        switch context.role {
        case .handle(.arcStart), .handle(.arcEnd):
            break
        case .handle(.point),
             .handle(.lineStart),
             .handle(.lineEnd),
             .handle(.circleCenter),
             .handle(.arcCenter),
             .splineControlPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires an arc endpoint source point."
            )
        }
        guard let feature = cadDocument.designGraph.nodes[context.featureID],
              case let .sketch(sketch) = feature.operation,
              case let .arc(arc) = sketch.entities[context.entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing source arc."
            )
        }
        return arc
    }

    private func sourceArcEndpointPoint(
        _ arc: SketchArc,
        endpoint: SelectionDimensionCurveEndpointRole,
        owner: String
    ) throws -> Point2D {
        let center = try resolvedPoint(arc.center, owner: "\(owner) center")
        let radius = try resolvedLength(arc.radius, owner: "\(owner) radius")
        let angle: Double
        switch endpoint {
        case .start:
            angle = try resolvedAngle(arc.startAngle, owner: "\(owner) angle")
        case .end:
            angle = try resolvedAngle(arc.endAngle, owner: "\(owner) angle")
        }
        return Point2D(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func sourceArcEndpointTargetPoint(
        center: Point2D,
        radius: Double,
        anchor: Point2D,
        targetDistance: Double,
        currentPoint: Point2D
    ) throws -> Point2D {
        guard radius > selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance application requires a positive source arc radius."
            )
        }
        let centerToAnchorX = anchor.x - center.x
        let centerToAnchorY = anchor.y - center.y
        let centerToAnchorDistance = hypot(centerToAnchorX, centerToAnchorY)
        if centerToAnchorDistance <= selectionDimensionEndpointTolerance {
            guard abs(targetDistance - radius) <= selectionDimensionEndpointTolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection arc endpoint distance target has no solution on the source arc circle."
                )
            }
            return currentPoint
        }

        let maximumDistance = radius + centerToAnchorDistance
        let minimumDistance = abs(radius - centerToAnchorDistance)
        guard targetDistance <= maximumDistance + selectionDimensionEndpointTolerance,
              targetDistance + selectionDimensionEndpointTolerance >= minimumDistance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance target has no solution on the source arc circle."
            )
        }

        let unitX = centerToAnchorX / centerToAnchorDistance
        let unitY = centerToAnchorY / centerToAnchorDistance
        let along = (
            radius * radius -
                targetDistance * targetDistance +
                centerToAnchorDistance * centerToAnchorDistance
        ) / (2.0 * centerToAnchorDistance)
        let heightSquared = radius * radius - along * along
        guard heightSquared >= -selectionDimensionEndpointTolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc endpoint distance target has no finite intersection solution."
            )
        }
        let height = sqrt(max(0.0, heightSquared))
        let base = Point2D(
            x: center.x + along * unitX,
            y: center.y + along * unitY
        )
        let first = Point2D(
            x: base.x - unitY * height,
            y: base.y + unitX * height
        )
        guard height > selectionDimensionEndpointTolerance else {
            return first
        }
        let second = Point2D(
            x: base.x + unitY * height,
            y: base.y - unitX * height
        )
        return squaredDistance(first, currentPoint) <= squaredDistance(second, currentPoint) ? first : second
    }

    private func squaredDistance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private func isArcEndpointRole(_ role: SelectionDimensionSourcePointRole) -> Bool {
        switch role {
        case .handle(.arcStart), .handle(.arcEnd):
            return true
        case .handle(.point),
             .handle(.lineStart),
             .handle(.lineEnd),
             .handle(.circleCenter),
             .handle(.arcCenter),
             .splineControlPoint:
            return false
        }
    }

    private func sourceArcEndpointParameters(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> SketchArcEndpointParameterResolver.EndpointParameters {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case let .arc(arc) = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection arc span application requires an existing source arc."
            )
        }
        return try SketchArcEndpointParameterResolver().endpointParameters(
            for: arc,
            plane: sketch.plane,
            in: self,
            owner: "Selection arc span application"
        )
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLength(point.x, owner: "\(owner) x"),
            y: try resolvedLength(point.y, owner: "\(owner) y")
        )
    }

    private func resolvedLength(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    private func resolvedAngle(
        _ expression: CADExpression,
        owner: String
    ) throws -> Double {
        let quantity = try cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite angle."
            )
        }
        return quantity.value
    }

    private func lineEndpointRole(
        parameter: Double,
        lineLength: Double
    ) throws -> SelectionDimensionLineEndpointRole {
        guard parameter.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires finite line endpoint parameters."
            )
        }
        if abs(parameter) <= selectionDimensionEndpointTolerance {
            return .start
        }
        if abs(parameter - lineLength) <= selectionDimensionEndpointTolerance {
            return .end
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Selection dimension application requires current line start and line end references."
        )
    }

    private func arcEndpointRole(
        parameter: Double,
        endpointParameters: SketchArcEndpointParameterResolver.EndpointParameters
    ) throws -> SelectionDimensionCurveEndpointRole {
        guard parameter.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection arc span application requires finite arc endpoint parameters."
            )
        }
        if abs(parameter - endpointParameters.start) <= selectionDimensionEndpointTolerance {
            return .start
        }
        if abs(parameter - endpointParameters.end) <= selectionDimensionEndpointTolerance {
            return .end
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Selection arc span application requires current arc start and arc end references."
        )
    }

    private func selectionReference(
        curve: CurveOutputReference,
        role: SelectionDimensionLineEndpointRole,
        lineLength: Double
    ) -> SelectionReference {
        switch role {
        case .start:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: 0.0
            )))
        case .end:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: lineLength
            )))
        }
    }

    private func selectionReference(
        curve: CurveOutputReference,
        role: SelectionDimensionCurveEndpointRole,
        arcEndpointParameters: SketchArcEndpointParameterResolver.EndpointParameters
    ) -> SelectionReference {
        switch role {
        case .start:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: arcEndpointParameters.start
            )))
        case .end:
            return .curve(.parameter(CurveParameterReference(
                curve: curve,
                parameter: arcEndpointParameters.end
            )))
        }
    }

    private func selectionReference(
        point context: SelectionDimensionSourcePointContext
    ) throws -> SelectionReference {
        switch context.role {
        case .handle(.lineStart):
            return .curve(.parameter(CurveParameterReference(
                curve: context.curve,
                parameter: 0.0
            )))
        case .handle(.lineEnd):
            return .curve(.parameter(CurveParameterReference(
                curve: context.curve,
                parameter: try sourceLineLength(
                    featureID: context.featureID,
                    entityID: context.entityID
                )
            )))
        case .handle(.circleCenter), .handle(.arcCenter):
            return .curve(.center(CurveCenterReference(curve: context.curve)))
        case .handle(.arcStart), .handle(.arcEnd):
            let endpointParameters = try sourceArcEndpointParameters(
                featureID: context.featureID,
                entityID: context.entityID
            )
            return selectionReference(
                curve: context.curve,
                role: context.role == .handle(.arcStart) ? .start : .end,
                arcEndpointParameters: endpointParameters
            )
        case .splineControlPoint(let index):
            return .curve(.controlPoint(CurveControlPointReference(
                curve: context.curve,
                controlPointIndex: index
            )))
        case .handle(.point):
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point distance application cannot persist standalone sketch point references yet."
            )
        }
    }

    private func lineAngleClosestToCurrent(
        referenceAngle: Double,
        targetAngle: Double,
        currentAngle: Double
    ) -> Double {
        let positive = referenceAngle + targetAngle
        let negative = referenceAngle - targetAngle
        if abs(normalizedSignedAngle(positive - currentAngle)) <=
            abs(normalizedSignedAngle(negative - currentAngle)) {
            return positive
        }
        return negative
    }

    private func normalizedSignedAngle(_ angle: Double) -> Double {
        let period = Double.pi * 2.0
        var result = angle.truncatingRemainder(dividingBy: period)
        if result > Double.pi {
            result -= period
        } else if result < -Double.pi {
            result += period
        }
        return result
    }

    private var selectionDimensionEndpointTolerance: Double {
        1.0e-8
    }
}

private enum SelectionDimensionLineEndpointRole: Equatable, Sendable {
    case start
    case end
}

private enum SelectionDimensionCurveEndpointRole: Equatable, Sendable {
    case start
    case end
}

private enum SelectionDimensionSourceApplication: Sendable {
    case lineLength(SelectionDimensionSourceLineContext)
    case circularRadius(SelectionDimensionSourceCircularContext)
    case lineRelativeAngle(SelectionDimensionSourceLineAngleContext)
    case arcSpanAngle(SelectionDimensionSourceArcAngleContext)
    case sourcePointDistance(SelectionDimensionSourcePointDistanceContext)
}

private struct SelectionDimensionSourceLineContext: Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var curve: CurveOutputReference
    var target: SelectionTarget
    var firstRole: SelectionDimensionLineEndpointRole
    var secondRole: SelectionDimensionLineEndpointRole
}

private struct SelectionDimensionSourceCircularContext: Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var curve: CurveOutputReference
    var target: SelectionTarget
}

private struct SelectionDimensionSourceLineAngleContext: Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var curve: CurveOutputReference
    var target: SelectionTarget
    var currentAngle: Double
    var referenceAngle: Double
}

private struct SelectionDimensionSourceArcAngleContext: Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var curve: CurveOutputReference
    var target: SelectionTarget
    var firstRole: SelectionDimensionCurveEndpointRole
    var secondRole: SelectionDimensionCurveEndpointRole
}

private struct SelectionDimensionSourcePointDistanceContext: Sendable {
    var first: SelectionDimensionSourcePointContext
    var second: SelectionDimensionSourcePointContext
}

private enum SelectionDimensionSourcePointRole: Equatable, Sendable {
    case handle(SketchEntityPointHandle)
    case splineControlPoint(Int)
}

private struct SelectionDimensionSourcePointContext: Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var curve: CurveOutputReference
    var plane: SketchPlane
    var target: SelectionTarget
    var role: SelectionDimensionSourcePointRole
}

private struct SourceLineAngleContext: Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var plane: SketchPlane
    var target: SelectionTarget
    var angle: Double
}
