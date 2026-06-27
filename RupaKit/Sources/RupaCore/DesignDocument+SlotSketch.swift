import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func createSlotSketch(
        target: SelectionTarget,
        width: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let resolvedWidth = try resolvedPositiveLengthValue(width, owner: "Slot width")
        let selection = try editableSketchEntity(for: target, operationName: "Slot")
        let name = "\(selection.feature.name ?? "Sketch Curve") Slot"

        switch selection.entity {
        case .line:
            let curveChain = try slotCurveChainPathSegments(for: selection)
            let result = try curveChain.allSatisfy(\.isLineSegment)
                ? SlotProfileBuilder().buildLineChainSlot(
                    points: slotLineChainPathPoints(for: selection),
                    plane: selection.sketch.plane,
                    width: width,
                    resolvedWidth: resolvedWidth
                )
                : SlotProfileBuilder().buildCurveChainSlot(
                    segments: curveChain,
                    plane: selection.sketch.plane,
                    width: width,
                    resolvedWidth: resolvedWidth
                )
            return try appendSketchFeature(
                name: name,
                sketch: result.sketch,
                typeID: .slot,
                geometryRole: .sketchProfile,
                properties: ObjectPropertySet(values: [
                    "source.kind": .text(curveChain.allSatisfy(\.isLineSegment) ? "lineChain" : "lineArcChain"),
                    "width": .length(result.width),
                    "path.length": .length(result.pathLength),
                    "radius": .length(result.capRadius),
                    ProfileTessellationPolicy.arcSegmentsPropertyID: .integer(32),
                ]),
                objectRegistry: objectRegistry
            )
        case .arc(let arc):
            let curveChain = try slotCurveChainPathSegments(for: selection)
            let result = try curveChain.count == 1
                ? SlotProfileBuilder().buildArcSlot(
                    source: arc,
                    plane: selection.sketch.plane,
                    resolvedRadius: resolvedPositiveLengthValue(arc.radius, owner: "Slot source arc radius"),
                    resolvedStartAngle: resolvedAngleValue(arc.startAngle, owner: "Slot source arc start angle"),
                    resolvedEndAngle: resolvedAngleValue(arc.endAngle, owner: "Slot source arc end angle"),
                    width: width,
                    resolvedWidth: resolvedWidth
                )
                : SlotProfileBuilder().buildCurveChainSlot(
                    segments: curveChain,
                    plane: selection.sketch.plane,
                    width: width,
                    resolvedWidth: resolvedWidth
                )
            return try appendSketchFeature(
                name: name,
                sketch: result.sketch,
                typeID: .slot,
                geometryRole: .sketchProfile,
                properties: ObjectPropertySet(values: [
                    "source.kind": .text(curveChain.count == 1 ? "arc" : "lineArcChain"),
                    "width": .length(result.width),
                    "path.length": .length(result.pathLength),
                    "radius": .length(result.capRadius),
                    ProfileTessellationPolicy.arcSegmentsPropertyID: .integer(32),
                ]),
                objectRegistry: objectRegistry
            )
        case .spline:
            let path = try slotSplinePath(for: selection)
            let result = try SlotProfileBuilder().buildSampledSplineSlot(
                path: path,
                plane: selection.sketch.plane,
                width: width,
                resolvedWidth: resolvedWidth
            )
            return try appendSketchFeature(
                name: name,
                sketch: result.sketch,
                typeID: .slot,
                geometryRole: .sketchProfile,
                properties: ObjectPropertySet(values: [
                    "source.kind": .text("spline"),
                    "width": .length(result.width),
                    "path.length": .length(result.pathLength),
                    "radius": .length(result.capRadius),
                    ProfileTessellationPolicy.arcSegmentsPropertyID: .integer(32),
                ]),
                objectRegistry: objectRegistry
            )
        case .circle:
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; circle targets are closed."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve target, not a point."
            )
        }
    }

    mutating func createSlotFromOffsetCurve(
        target: SelectionTarget,
        width: CADExpression,
        options: OffsetCurveOptions,
        vertexHandle: SketchEntityPointHandle?,
        objectRegistry: ObjectTypeRegistry
    ) throws -> FeatureID {
        guard vertexHandle == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode requires a selected open curve target, not a vertex handle."
            )
        }
        guard options.isSymmetric == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode already creates symmetric output and does not accept the planar symmetric option."
            )
        }
        guard options.gapFill == .round else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode closes with tangent arc caps and does not accept planar gap-fill options."
            )
        }
        guard options.supportTarget == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Offset Curve Slot mode does not accept an edge support target."
            )
        }
        return try createSlotSketch(
            target: target,
            width: width,
            objectRegistry: objectRegistry
        )
    }

    private func slotLineChainPathPoints(
        for selection: EditableSketchEntitySelection
    ) throws -> [SlotProfileBuilder.PathPoint] {
        let vertices = try SlotLineChainResolver().resolve(
            sketch: selection.sketch,
            selectedLineID: selection.entityID
        )
        return try vertices.map { vertex in
            guard let resolved = try resolvedSlotPoint(
                vertex.reference,
                in: selection.sketch,
                owner: "Slot source line chain"
            ) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source line chain requires line endpoint references."
                )
            }
            for connectedReference in vertex.connectedLineEndpointReferences {
                guard let connected = try resolvedSlotPoint(
                    connectedReference,
                    in: selection.sketch,
                    owner: "Slot source line chain"
                ) else {
                    continue
                }
                let deltaX = connected.x - resolved.x
                let deltaY = connected.y - resolved.y
                guard deltaX * deltaX + deltaY * deltaY <= 1.0e-18 else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source line chain requires coincident endpoints to resolve to the same point."
                    )
                }
            }
            return SlotProfileBuilder.PathPoint(
                point: try slotSketchPoint(vertex.reference, in: selection.sketch, owner: "Slot source line chain"),
                resolved: Point2D(x: resolved.x, y: resolved.y)
            )
        }
    }

    private func slotCurveChainPathSegments(
        for selection: EditableSketchEntitySelection
    ) throws -> [SlotProfileBuilder.CurvePathSegment] {
        let pathSegments = try SlotCurveChainResolver().resolve(
            sketch: selection.sketch,
            selectedEntityID: selection.entityID
        )
        return try pathSegments.map { segment in
            guard let entity = selection.sketch.entities[segment.entityID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Slot source curve chain requires existing sketch entities."
                )
            }
            switch entity {
            case .line:
                let start = try resolvedPathPoint(
                    segment.startReference,
                    in: selection.sketch,
                    owner: "Slot source curve chain"
                )
                let end = try resolvedPathPoint(
                    segment.endReference,
                    in: selection.sketch,
                    owner: "Slot source curve chain"
                )
                return .line(SlotProfileBuilder.LinePathSegment(start: start, end: end))
            case .arc(let arc):
                let center = try resolvedPathPoint(
                    .arcCenter(segment.entityID),
                    in: selection.sketch,
                    owner: "Slot source curve chain"
                )
                let radius = try resolvedPositiveLengthValue(
                    arc.radius,
                    owner: "Slot source curve chain arc radius"
                )
                let startAngle = try resolvedAngleValue(
                    arc.startAngle,
                    owner: "Slot source curve chain arc start angle"
                )
                let endAngle = try resolvedAngleValue(
                    arc.endAngle,
                    owner: "Slot source curve chain arc end angle"
                )
                let traversesForward: Bool
                switch (segment.startReference, segment.endReference) {
                case (.arcStart(let firstID), .arcEnd(let secondID)) where firstID == segment.entityID && secondID == segment.entityID:
                    traversesForward = true
                case (.arcEnd(let firstID), .arcStart(let secondID)) where firstID == segment.entityID && secondID == segment.entityID:
                    traversesForward = false
                default:
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Slot source arc chain requires arc endpoint references."
                    )
                }
                return .arc(SlotProfileBuilder.ArcPathSegment(
                    center: center,
                    radius: radius,
                    startAngle: traversesForward ? startAngle : endAngle,
                    endAngle: traversesForward ? endAngle : startAngle,
                    sweepSign: traversesForward ? 1.0 : -1.0
                ))
            case .point, .circle, .spline:
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source curve chain supports line and arc sketch entities."
                )
            }
        }
    }

    private func slotSplinePath(
        for selection: EditableSketchEntitySelection
    ) throws -> SlotProfileBuilder.SampledSplinePath {
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot spline path resolution requires a selected spline target."
            )
        }
        guard spline.isClosed == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; closed spline targets are not supported."
            )
        }

        let controlPoints = try spline.controlPoints.map { point in
            let resolved = try resolvedSlotPoint(point, owner: "Slot source spline")
            return Point2D(x: resolved.x, y: resolved.y)
        }
        let samplesPerSegment = SlotProfileBuilder.defaultSplineSamplesPerSegment
        let samples = SketchCurveSampler(samplesPerSegment: samplesPerSegment)
            .splineSamples(for: controlPoints)
        var points: [Point2D] = []
        points.reserveCapacity(samples.count)
        for sample in samples {
            if let last = points.last {
                let deltaX = sample.point.x - last.x
                let deltaY = sample.point.y - last.y
                if deltaX * deltaX + deltaY * deltaY <= 1.0e-24 {
                    continue
                }
            }
            points.append(sample.point)
        }
        guard points.count >= 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot source spline must have a non-zero sampled length."
            )
        }
        return SlotProfileBuilder.SampledSplinePath(
            points: points,
            samplesPerSegment: samplesPerSegment
        )
    }

    private func resolvedSlotPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> (x: Double, y: Double)? {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return try resolvedSlotPoint(point, owner: owner)
        case let .lineStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return try resolvedSlotPoint(line.start, owner: owner)
        case let .lineEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .line(line) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return try resolvedSlotPoint(line.end, owner: owner)
        case let .circleCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .circle(circle) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return try resolvedSlotPoint(circle.center, owner: owner)
        case let .arcCenter(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return try resolvedSlotPoint(arc.center, owner: owner)
        case let .arcStart(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return try slotPointOnArc(arc, angle: arc.startAngle, owner: owner)
        case let .arcEnd(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .arc(arc) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return try slotPointOnArc(arc, angle: arc.endAngle, owner: owner)
        case let .splineControlPoint(entityID, index):
            guard let entity = sketch.entities[entityID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.indices.contains(index) else {
                throw invalidSlotPointReference(owner)
            }
            return try resolvedSlotPoint(spline.controlPoints[index], owner: owner)
        case .circleRadius, .arcRadius:
            return nil
        }
    }

    private func resolvedSlotPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    private func slotPointOnArc(
        _ arc: SketchArc,
        angle: CADExpression,
        owner: String
    ) throws -> (x: Double, y: Double) {
        let center = try resolvedSlotPoint(arc.center, owner: owner)
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let resolvedAngle = try resolvedAngleValue(angle, owner: "\(owner) arc angle")
        return (
            x: center.x + cos(resolvedAngle) * radius,
            y: center.y + sin(resolvedAngle) * radius
        )
    }

    private func invalidSlotPointReference(_ owner: String) -> EditorError {
        EditorError(
            code: .referenceUnresolved,
            message: "\(owner) references an unsupported sketch point."
        )
    }

    private func resolvedPathPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Point2D {
        guard let point = try resolvedSlotPoint(reference, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-like sketch references."
            )
        }
        return Point2D(x: point.x, y: point.y)
    }

    private func slotSketchPoint(
        _ reference: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchPoint {
        switch reference {
        case .lineStart(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line(let line) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return line.start
        case .lineEnd(let entityID):
            guard let entity = sketch.entities[entityID],
                  case .line(let line) = entity else {
                throw invalidSlotPointReference(owner)
            }
            return line.end
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires line endpoint references."
            )
        }
    }
}
