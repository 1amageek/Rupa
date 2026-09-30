import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func offsetCurve(
        target: SelectionTarget,
        distance: CADExpression,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID] {
        if options.mode == .slot {
            let featureID = try createSlotFromOffsetCurve(
                target: target,
                width: distance,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return [featureID]
        }
        let distanceMeters = try resolvedLengthValue(distance, owner: "Curve offset distance")
        guard abs(distanceMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Curve offset distance must not be zero."
            )
        }
        if options.supportTarget != nil {
            guard case .edge = target.component else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve offset support target is only valid for generated edge Offset Edge dispatch."
                )
            }
        }

        switch target.component {
        case .sketchEntity:
            let selection = try editableSketchEntity(for: target, operationName: "Curve offset")
            if let vertexHandle {
                try validateOffsetCurveVertexOptions(options)
                try offsetSketchVertex(
                    target: target,
                    handle: vertexHandle,
                    distance: distance,
                    objectRegistry: objectRegistry
                )
                return [selection.featureID]
            }
            let name = "\(selection.feature.name ?? "Sketch Curve") Offset"
            // A joined curve offsets as one curve, whichever of its members is selected.
            if let group = joinedCurveGroup(featureID: selection.featureID, entityID: selection.entityID) {
                let positive = try offsetJoinedChain(group, sketch: selection.sketch, distance: distanceMeters, gapFill: options.gapFill)
                if options.isSymmetric {
                    let negative = try offsetJoinedChain(group, sketch: selection.sketch, distance: -distanceMeters, gapFill: options.gapFill)
                    return [
                        try createSplineSketch(name: "\(name) Positive", plane: selection.sketch.plane, spline: positive, objectRegistry: objectRegistry),
                        try createSplineSketch(name: "\(name) Negative", plane: selection.sketch.plane, spline: negative, objectRegistry: objectRegistry),
                    ]
                }
                return [try createSplineSketch(name: name, plane: selection.sketch.plane, spline: positive, objectRegistry: objectRegistry)]
            }
            switch selection.entity {
            case .line(let line):
                let shiftedLine = try offsetLine(
                    line,
                    distance: distance,
                    owner: "Curve offset"
                )
                if options.isSymmetric {
                    let mirroredLine = try offsetLine(
                        line,
                        distance: negatedExpression(distance),
                        owner: "Curve offset"
                    )
                    let firstID = try createLineSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        start: shiftedLine.start,
                        end: shiftedLine.end,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createLineSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        start: mirroredLine.start,
                        end: mirroredLine.end,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createLineSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    start: shiftedLine.start,
                    end: shiftedLine.end,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .circle(let circle):
                let offsetRadius = try offsetRadiusExpression(
                    circle.radius,
                    distance: distance,
                    resolvedDistance: distanceMeters,
                    owner: "Curve offset circle"
                )
                if options.isSymmetric {
                    let mirroredRadius = try offsetRadiusExpression(
                        circle.radius,
                        distance: negatedExpression(distance),
                        resolvedDistance: -distanceMeters,
                        owner: "Curve offset circle"
                    )
                    let firstID = try createCircleSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        center: circle.center,
                        radius: offsetRadius,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createCircleSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        center: circle.center,
                        radius: mirroredRadius,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createCircleSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    center: circle.center,
                    radius: offsetRadius,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .arc(let arc):
                let offsetRadius = try offsetRadiusExpression(
                    arc.radius,
                    distance: distance,
                    resolvedDistance: distanceMeters,
                    owner: "Curve offset arc"
                )
                if options.isSymmetric {
                    let mirroredRadius = try offsetRadiusExpression(
                        arc.radius,
                        distance: negatedExpression(distance),
                        resolvedDistance: -distanceMeters,
                        owner: "Curve offset arc"
                    )
                    let firstID = try createArcSketch(
                        name: "\(name) Positive",
                        plane: selection.sketch.plane,
                        center: arc.center,
                        radius: offsetRadius,
                        startAngle: arc.startAngle,
                        endAngle: arc.endAngle,
                        objectRegistry: objectRegistry
                    )
                    let secondID = try createArcSketch(
                        name: "\(name) Negative",
                        plane: selection.sketch.plane,
                        center: arc.center,
                        radius: mirroredRadius,
                        startAngle: arc.startAngle,
                        endAngle: arc.endAngle,
                        objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createArcSketch(
                    name: name,
                    plane: selection.sketch.plane,
                    center: arc.center,
                    radius: offsetRadius,
                    startAngle: arc.startAngle,
                    endAngle: arc.endAngle,
                    objectRegistry: objectRegistry
                )
                return [featureID]
            case .point:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve offset source point entities do not identify the adjacent curve sides required by Offset Vertex. Select a source line or arc endpoint with a vertex handle."
                )
            case .spline(let spline):
                // Swift-CAD fits the offset of the spline's own curve, segment by segment whatever its
                // degree and knots, as a cubic chain within the modeling distance.
                let curve = try resolvedSketchSplineCurve(spline, owner: "Curve offset spline")
                let offsetter = CubicBezierChainOffset(tolerance: .standard)
                func offsetSpline(_ signedDistance: Double) throws -> SketchSpline {
                    // Corners join by the gap fill.
                    let gapFill: CubicBezierChainOffset.GapFill = switch options.gapFill {
                    case .round: .round
                    case .linear: .linear
                    case .natural: .natural
                    }
                    let chain: [Point2D]
                    do {
                        chain = try offsetter.offset(of: curve, distance: signedDistance, gapFill: gapFill)
                    } catch let error as KernelError {
                        throw EditorError(code: .commandInvalid, message: "Offset Planar Curve: \(error.message)")
                    }
                    return SketchSpline(
                        controlPoints: chain.map { sketchPoint(x: $0.x, y: $0.y) },
                        isClosed: spline.isClosed
                    )
                }
                if options.isSymmetric {
                    let firstID = try createSplineSketch(
                        name: "\(name) Positive", plane: selection.sketch.plane,
                        spline: try offsetSpline(distanceMeters), objectRegistry: objectRegistry
                    )
                    let secondID = try createSplineSketch(
                        name: "\(name) Negative", plane: selection.sketch.plane,
                        spline: try offsetSpline(-distanceMeters), objectRegistry: objectRegistry
                    )
                    return [firstID, secondID]
                }
                let featureID = try createSplineSketch(
                    name: name, plane: selection.sketch.plane,
                    spline: try offsetSpline(distanceMeters), objectRegistry: objectRegistry
                )
                return [featureID]
            }
        case .region:
            let featureIDs = try offsetProfileRegion(
                target: target,
                distanceMeters: distanceMeters,
                options: options,
                vertexHandle: vertexHandle,
                objectRegistry: objectRegistry
            )
            return featureIDs
        case .face:
            guard vertexHandle == nil else {
                throw EditorError(code: .commandInvalid, message: "Offset Face Loop does not take a sketch vertex handle.")
            }
            return [try offsetFaceLoops(
                targets: [target], distance: distance, isSymmetric: options.isSymmetric, gapFill: options.gapFill,
                isIndividual: true, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )]
        case .edge:
            guard vertexHandle == nil else {
                throw EditorError(code: .commandInvalid, message: "Offset Edge does not take a sketch vertex handle.")
            }
            guard let supportFace = options.supportTarget else {
                throw EditorError(code: .commandInvalid, message: EdgeOffsetSupportFaceResolver.missingSupportFaceMessage)
            }
            return [try offsetEdges(
                targets: [target], supportFace: supportFace, distance: distance, isSymmetric: options.isSymmetric,
                gapFill: options.gapFill, objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
            )]
        case .vertex:
            guard vertexHandle == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Generated vertex Offset Vertex dispatch uses the selected generated vertex target and does not accept an additional sketch vertex handle."
                )
            }
            try validateOffsetCurveVertexOptions(options)
            let resolvedTarget = try generatedSketchVertexOffsetTarget(
                for: target,
                objectRegistry: objectRegistry,
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
            )
            try offsetSketchVertex(
                target: resolvedTarget.target,
                handle: resolvedTarget.handle,
                distance: distance,
                objectRegistry: objectRegistry
            )
            return [resolvedTarget.featureID]
        case .object, .constructionPlane:
            throw EditorError(
                code: .referenceUnresolved,
                message: "Curve offset requires a selected curve, region, vertex, face loop, or edge target."
            )
        }
    }

    private func negatedExpression(_ expression: CADExpression) -> CADExpression {
        .multiply(expression, .constant(.scalar(-1.0)))
    }

    /// The line moved by `distance` along its left normal (the direction turned a quarter turn
    /// counterclockwise), the normal an expression of the line's own ends, so the offset keeps
    /// its distance when the source line turns.
    private func offsetLine(
        _ line: SketchLine,
        distance: CADExpression,
        owner: String
    ) throws -> SketchLine {
        let startX = try resolvedLengthValue(line.start.x, owner: "\(owner) line start x")
        let startY = try resolvedLengthValue(line.start.y, owner: "\(owner) line start y")
        let endX = try resolvedLengthValue(line.end.x, owner: "\(owner) line end x")
        let endY = try resolvedLengthValue(line.end.y, owner: "\(owner) line end y")
        guard hypot(endX - startX, endY - startY) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a line with non-zero length."
            )
        }
        let direction = unitDirectionExpressions(from: line.start, to: line.end)
        let normal = (x: CADExpression.multiply(direction.y, .scalar(-1)), y: direction.x)
        return SketchLine(
            start: offsetPoint(line.start, distance: distance, normal: normal),
            end: offsetPoint(line.end, distance: distance, normal: normal)
        )
    }

    private func offsetPoint(
        _ point: SketchPoint,
        distance: CADExpression,
        normal: (x: CADExpression, y: CADExpression)
    ) -> SketchPoint {
        SketchPoint(
            x: .add(point.x, .multiply(distance, normal.x)),
            y: .add(point.y, .multiply(distance, normal.y))
        )
    }

    private func validateOffsetCurveVertexOptions(_ options: OffsetCurveOptions) throws {
        guard options.mode == .offset else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode requires a selected open curve target, not a vertex handle."
            )
        }
        guard options == OffsetCurveOptions() else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve vertex dispatch does not accept planar curve options such as symmetric output or gap fill."
            )
        }
    }

    private func offsetRadiusExpression(
        _ radius: CADExpression,
        distance: CADExpression,
        resolvedDistance: Double,
        owner: String
    ) throws -> CADExpression {
        let radiusMeters = try resolvedPositiveLengthValue(radius, owner: "\(owner) radius")
        guard radiusMeters + resolvedDistance > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) offset would collapse the radius."
            )
        }
        return .add(radius, distance)
    }
}
