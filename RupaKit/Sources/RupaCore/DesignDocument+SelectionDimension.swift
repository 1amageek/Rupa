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
            case (.curve(.parameter(_)), .curve(.parameter(_))):
                return .lineLength(try sourceLineEndpointDimensionContext(for: dimension))
            case (.curve(.center(let center)), .curve(let radialReference)):
                return .circularRadius(try sourceCircularRadiusDimensionContext(
                    center: center,
                    radialReference: radialReference
                ))
            case (.curve(let radialReference), .curve(.center(let center))):
                return .circularRadius(try sourceCircularRadiusDimensionContext(
                    center: center,
                    radialReference: radialReference
                ))
            default:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Selection dimension application currently supports source line length and source circle/arc radius distance dimensions."
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

        let target = SelectionTarget(
            sceneNodeID: try sketchSceneNodeID(featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: featureID,
                    entityID: entityID
                )
            )
        )
        return SelectionDimensionSourceLineContext(
            featureID: featureID,
            entityID: entityID,
            curve: firstParameter.curve,
            target: target,
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

        let target = SelectionTarget(
            sceneNodeID: try sketchSceneNodeID(featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: featureID,
                    entityID: entityID
                )
            )
        )
        return SelectionDimensionSourceCircularContext(
            featureID: featureID,
            entityID: entityID,
            curve: center.curve,
            target: target
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

        let target = SelectionTarget(
            sceneNodeID: try sketchSceneNodeID(featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: featureID,
                    entityID: entityID
                )
            )
        )
        return SelectionDimensionSourceArcAngleContext(
            featureID: featureID,
            entityID: entityID,
            curve: firstParameter.curve,
            target: target,
            firstRole: firstRole,
            secondRole: secondRole
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
        let target = SelectionTarget(
            sceneNodeID: try sketchSceneNodeID(featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: featureID,
                    entityID: entityID
                )
            )
        )
        return SourceLineAngleContext(
            featureID: featureID,
            entityID: entityID,
            plane: sketch.plane,
            target: target,
            angle: atan2(dy, dx)
        )
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

private struct SourceLineAngleContext: Sendable {
    var featureID: FeatureID
    var entityID: SketchEntityID
    var plane: SketchPlane
    var target: SelectionTarget
    var angle: Double
}
