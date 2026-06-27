import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public mutating func setSketchEntityDimension(
        target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        value: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let resolvedValue = try resolvedSketchEntityDimensionValue(
            value,
            kind: kind,
            owner: "Sketch entity dimension"
        )
        let editTarget = try sketchEntityDimensionEditTarget(
            for: target,
            kind: kind,
            objectRegistry: objectRegistry
        )
        let selection = try editableSketchEntity(for: editTarget, operationName: "Sketch entity dimension update")
        try validateResolvedSketchEntityDimensionValue(
            resolvedValue,
            kind: kind,
            entity: selection.entity
        )
        var feature = selection.feature
        var sketch = selection.sketch
        let pointPropagator = SketchPointConstraintPropagator(parameters: cadDocument.parameters)
        switch selection.entity {
        case .line(let line):
            guard kind == .length || kind == .angle else {
                throw incompatibleSketchDimension(kind, entityKind: "line")
            }
            if kind == .length,
               let axis = try rectangleSideDimensionAxis(
                in: sketch,
                entityID: selection.entityID
            ) {
                try updateRectangleSketchForSideDimension(
                    &sketch,
                    axis: axis,
                    length: value,
                    resolvedLength: resolvedValue
                )
            } else {
                let startReference = SketchReference.lineStart(selection.entityID)
                let endReference = SketchReference.lineEnd(selection.entityID)
                let startAnchored = pointPropagator.isAnchored(startReference, in: sketch)
                let endAnchored = pointPropagator.isAnchored(endReference, in: sketch)
                let metrics = try resolvedLineMetrics(line, owner: "Sketch line dimension update")
                if kind == .angle {
                    try validateLineAngleDimensionAgainstDirectOrientationConstraints(
                        resolvedValue,
                        lineID: selection.entityID,
                        sketch: sketch,
                        owner: "Sketch line dimension update"
                    )
                }
                let isConflictingFixedDimension: Bool
                switch kind {
                case .length:
                    isConflictingFixedDimension = abs(metrics.length - resolvedValue) > 1.0e-12
                case .angle:
                    isConflictingFixedDimension = angularDistance(metrics.angleRadians, resolvedValue) > 1.0e-12
                case .radius, .diameter:
                    isConflictingFixedDimension = true
                }
                guard startAnchored == false || endAnchored == false || isConflictingFixedDimension == false else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch line dimension update cannot change a line with both endpoints fixed."
                    )
                }
                let movedReference: SketchReference?
                if startAnchored && endAnchored {
                    movedReference = nil
                } else if endAnchored && startAnchored == false {
                    let nextLine: SketchLine
                    switch kind {
                    case .length:
                        nextLine = try resizedLinePreservingEnd(
                            line,
                            length: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .angle:
                        nextLine = try angledLinePreservingEnd(
                            line,
                            angleRadians: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .radius, .diameter:
                        throw incompatibleSketchDimension(kind, entityKind: "line")
                    }
                    sketch.entities[selection.entityID] = .line(nextLine)
                    movedReference = startReference
                } else {
                    let nextLine: SketchLine
                    switch kind {
                    case .length:
                        nextLine = try resizedLine(
                            line,
                            length: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .angle:
                        nextLine = try angledLinePreservingStart(
                            line,
                            angleRadians: resolvedValue,
                            owner: "Sketch line dimension update"
                        )
                    case .radius, .diameter:
                        throw incompatibleSketchDimension(kind, entityKind: "line")
                    }
                    sketch.entities[selection.entityID] = .line(nextLine)
                    movedReference = endReference
                }
                if let movedReference {
                    try pointPropagator.propagate(
                        from: movedReference,
                        in: &sketch,
                        owner: "Sketch line dimension update"
                    )
                }
            }
        case .circle(var circle):
            guard kind == .radius || kind == .diameter else {
                throw incompatibleSketchDimension(kind, entityKind: "circle")
            }
            try pointPropagator.validateCanResizeCircularEntity(
                selection.entityID,
                in: sketch,
                owner: "Sketch entity dimension update"
            )
            circle.radius = try radiusExpression(for: kind, value: value)
            sketch.entities[selection.entityID] = .circle(circle)
            try pointPropagator.propagateCircularRadius(
                from: selection.entityID,
                in: &sketch,
                owner: "Sketch entity dimension update"
            )
        case .arc(var arc):
            guard kind == .radius || kind == .diameter || kind == .angle else {
                throw incompatibleSketchDimension(kind, entityKind: "arc")
            }
            if kind == .angle {
                let startReference = SketchReference.arcStart(selection.entityID)
                let endReference = SketchReference.arcEnd(selection.entityID)
                let startAnchored = pointPropagator.isAnchored(startReference, in: sketch)
                let endAnchored = pointPropagator.isAnchored(endReference, in: sketch)
                let startAngle = try resolvedAngleValue(
                    arc.startAngle,
                    owner: "Sketch entity dimension update start angle"
                )
                let endAngle = try resolvedAngleValue(
                    arc.endAngle,
                    owner: "Sketch entity dimension update end angle"
                )
                let currentSpan = try normalizedPartialArcSpan(
                    startAngle: startAngle,
                    endAngle: endAngle
                )
                guard startAnchored == false || endAnchored == false || abs(currentSpan - resolvedValue) <= 1.0e-12 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch arc span dimension update cannot change an arc with both endpoints fixed."
                    )
                }
                let movedReference: SketchReference?
                if startAnchored && endAnchored {
                    movedReference = nil
                } else if endAnchored && startAnchored == false {
                    arc.startAngle = .angle(endAngle - resolvedValue, .radian)
                    movedReference = startReference
                } else {
                    arc.endAngle = .angle(startAngle + resolvedValue, .radian)
                    movedReference = endReference
                }
                try validateArc(arc, owner: "Sketch entity dimension update")
                sketch.entities[selection.entityID] = .arc(arc)
                if let movedReference {
                    try pointPropagator.propagate(
                        from: movedReference,
                        in: &sketch,
                        owner: "Sketch entity dimension update"
                    )
                }
            } else {
                if let profileSketch = try profileArcRadiusDimensionSketch(
                    featureID: selection.featureID,
                    entityID: selection.entityID,
                    sketch: sketch,
                    kind: kind,
                    value: value
                ) {
                    sketch = profileSketch
                    break
                }
                try pointPropagator.validateCanResizeCircularEntity(
                    selection.entityID,
                    in: sketch,
                    owner: "Sketch entity dimension update"
                )
                arc.radius = try radiusExpression(for: kind, value: value)
                sketch.entities[selection.entityID] = .arc(arc)
            }
            if kind != .angle {
                try pointPropagator.propagateCircularRadius(
                    from: selection.entityID,
                    in: &sketch,
                    owner: "Sketch entity dimension update"
                )
            }
        case .point:
            throw incompatibleSketchDimension(kind, entityKind: "point")
        case .spline:
            throw incompatibleSketchDimension(kind, entityKind: "spline")
        }
        sketch.dimensions = dimensionsAfterSettingEntityDimension(
            sketch.dimensions,
            entityID: selection.entityID,
            entity: selection.entity,
            kind: kind,
            value: value
        )

        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Sketch entity dimension update"
        )
    }

    private func sketchEntityDimensionEditTarget(
        for target: SelectionTarget,
        kind: SketchEntityDimensionKind,
        objectRegistry: ObjectTypeRegistry
    ) throws -> SelectionTarget {
        if case .sketchEntity = target.component {
            return target
        }
        guard case .edge = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch entity dimension update requires a sketch entity or editable generated edge target."
            )
        }
        let summary = try SketchDimensionSummaryService().summarize(
            document: self,
            targets: [target],
            objectRegistry: objectRegistry
        )
        guard let entry = summary.entries.first(where: { $0.kind == kind }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch entity dimension update found no editable \(kind.rawValue) dimension for the generated edge target."
            )
        }
        return entry.target
    }

    func radiusExpression(
        for kind: SketchEntityDimensionKind,
        value: CADExpression
    ) throws -> CADExpression {
        switch kind {
        case .radius:
            return value
        case .diameter:
            return .divide(value, .scalar(2.0))
        case .length, .angle:
            throw incompatibleSketchDimension(kind, entityKind: "circular")
        }
    }

    private func resolvedSketchEntityDimensionValue(
        _ expression: CADExpression,
        kind: SketchEntityDimensionKind,
        owner: String
    ) throws -> Double {
        switch kind {
        case .length, .radius, .diameter:
            return try resolvedLengthValue(expression, owner: owner)
        case .angle:
            return try resolvedAngleValue(expression, owner: owner)
        }
    }

    private func validateResolvedSketchEntityDimensionValue(
        _ value: Double,
        kind: SketchEntityDimensionKind,
        entity: SketchEntity
    ) throws {
        switch kind {
        case .length, .radius, .diameter:
            guard value > 0.0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch entity dimension must be greater than zero."
                )
            }
        case .angle:
            guard value.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Sketch entity angle dimension must be finite."
                )
            }
            if case .arc = entity {
                guard value > 0.0 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch arc span angle dimension must be greater than zero."
                    )
                }
                guard value < Double.pi * 2.0 - ModelingTolerance.standard.angle else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Sketch arc span angle dimension must be less than a full circle."
                    )
                }
            }
        }
    }

    private func incompatibleSketchDimension(
        _ kind: SketchEntityDimensionKind,
        entityKind: String
    ) -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Sketch \(entityKind) does not support \(kind.rawValue) dimensions."
        )
    }

    private func dimensionsAfterSettingEntityDimension(
        _ dimensions: [SketchDimension],
        entityID: SketchEntityID,
        entity: SketchEntity,
        kind: SketchEntityDimensionKind,
        value: CADExpression
    ) -> [SketchDimension] {
        var next = dimensions.filter { dimension in
            switch kind {
            case .length:
                return isLineLengthDimension(dimension, entityID: entityID) == false
            case .radius, .diameter:
                return isCircularSizeDimension(dimension, entityID: entityID) == false
            case .angle:
                switch entity {
                case .line:
                    return isLineAngleDimension(dimension, entityID: entityID) == false
                case .arc:
                    return isArcAngleDimension(dimension, entityID: entityID) == false
                case .point, .circle, .spline:
                    return true
                }
            }
        }
        switch kind {
        case .length:
            next.append(.distance(from: .lineStart(entityID), to: .lineEnd(entityID), value: value))
        case .radius:
            next.append(.radius(entity: entityID, value: value))
        case .diameter:
            next.append(.diameter(entity: entityID, value: value))
        case .angle:
            switch entity {
            case .line:
                next.append(.angle(from: .lineStart(entityID), to: .lineEnd(entityID), value: value))
            case .arc:
                next.append(.angle(from: .arcStart(entityID), to: .arcEnd(entityID), value: value))
            case .point, .circle, .spline:
                return next
            }
        }
        return next
    }

    private func isLineLengthDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        guard case let .distance(first, second, _) = dimension else {
            return false
        }
        return referencesLineEndpoints(first, second, entityID: entityID)
    }

    private func referencesLineEndpoints(
        _ first: SketchReference,
        _ second: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch (first, second) {
        case (.lineStart(let firstID), .lineEnd(let secondID)),
             (.lineEnd(let firstID), .lineStart(let secondID)):
            return firstID == entityID && secondID == entityID
        default:
            return false
        }
    }

    private func isLineAngleDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        guard case let .angle(first, second, _) = dimension else {
            return false
        }
        return referencesLineEndpoints(first, second, entityID: entityID)
    }

    func isCircularSizeDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        switch dimension {
        case .radius(let id, _), .diameter(let id, _):
            return id == entityID
        case .distance, .angle:
            return false
        }
    }

    private func isArcAngleDimension(
        _ dimension: SketchDimension,
        entityID: SketchEntityID
    ) -> Bool {
        guard case let .angle(first, second, _) = dimension else {
            return false
        }
        return referencesArcEndpoints(first, second, entityID: entityID)
    }

    private func referencesArcEndpoints(
        _ first: SketchReference,
        _ second: SketchReference,
        entityID: SketchEntityID
    ) -> Bool {
        switch (first, second) {
        case (.arcStart(let firstID), .arcEnd(let secondID)),
             (.arcEnd(let firstID), .arcStart(let secondID)):
            return firstID == entityID && secondID == entityID
        default:
            return false
        }
    }

}
