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
        guard dimension.kind == .distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application currently supports distance dimensions only."
            )
        }

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
                message: "Selection dimension application currently supports source line length and source circle/arc radius dimensions."
            )
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

    private var selectionDimensionEndpointTolerance: Double {
        1.0e-8
    }
}

private enum SelectionDimensionLineEndpointRole: Equatable, Sendable {
    case start
    case end
}

private enum SelectionDimensionSourceApplication: Sendable {
    case lineLength(SelectionDimensionSourceLineContext)
    case circularRadius(SelectionDimensionSourceCircularContext)
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
