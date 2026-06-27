import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func refreshedSketchDimension(
        _ dimension: SketchDimension,
        in sketch: Sketch,
        owner: String
    ) throws -> SketchDimension {
        switch dimension {
        case .distance(let from, let to, _):
            let distance = try measuredSketchDistanceDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .distance(from: from, to: to, value: .length(distance, .meter))
        case .angle(let from, let to, _):
            let angle = try measuredSketchAngleDimension(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
            return .angle(from: from, to: to, value: .angle(angle, .radian))
        case .radius(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .radius(entity: entityID, value: .length(radius, .meter))
        case .diameter(let entityID, _):
            let radius = try measuredSketchCircularRadius(
                entityID,
                in: sketch,
                owner: owner
            )
            return .diameter(entity: entityID, value: .length(radius * 2.0, .meter))
        }
    }

    func measuredSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        let entityID: SketchEntityID
        switch (from, to) {
        case (.arcStart(let firstID), .arcEnd(let secondID)) where firstID == secondID:
            entityID = firstID
        case (.arcEnd(let firstID), .arcStart(let secondID)) where firstID == secondID:
            entityID = firstID
        default:
            return try measuredConnectedSketchArcSpanAngle(
                from: from,
                to: to,
                in: sketch,
                owner: owner
            )
        }
        guard let entity = sketch.entities[entityID],
              case .arc(let arc) = entity else {
            return nil
        }
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
    }

    private func measuredSketchDistanceDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed distance references."
            )
        }
        return hypot(second.x - first.x, second.y - first.y)
    }

    private func measuredSketchAngleDimension(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        if let arcSpan = try measuredSketchArcSpanAngle(
            from: from,
            to: to,
            in: sketch,
            owner: owner
        ) {
            return arcSpan
        }
        guard let first = try resolvedPoint(from, in: sketch, owner: owner),
              let second = try resolvedPoint(to, in: sketch, owner: owner) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires point-backed angle references."
            )
        }
        return atan2(second.y - first.y, second.x - first.x)
    }

    private func measuredConnectedSketchArcSpanAngle(
        from: SketchReference,
        to: SketchReference,
        in sketch: Sketch,
        owner: String
    ) throws -> Double? {
        guard let fromEndpoint = sketchArcPathEndpoint(for: from),
              let toEndpoint = sketchArcPathEndpoint(for: to),
              let seedEntity = sketch.entities[fromEndpoint.entityID],
              case .arc(let seedArc) = seedEntity else {
            return nil
        }
        let seedGeometry = try sketchArcPathGeometry(
            entityID: fromEndpoint.entityID,
            arc: seedArc,
            owner: owner
        )
        var geometries: [SketchEntityID: SketchArcPathGeometry] = [:]
        for (entityID, entity) in sketch.entities {
            guard case .arc(let arc) = entity else {
                continue
            }
            let geometry = try sketchArcPathGeometry(
                entityID: entityID,
                arc: arc,
                owner: owner
            )
            guard sketchArcPathGeometry(geometry, matchesCircleOf: seedGeometry) else {
                continue
            }
            geometries[entityID] = geometry
        }
        guard geometries[toEndpoint.entityID] != nil else {
            return nil
        }
        let spans = [
            connectedSketchArcSpanAngle(
                from: fromEndpoint,
                to: toEndpoint,
                geometries: geometries
            ),
            connectedSketchArcSpanAngle(
                from: toEndpoint,
                to: fromEndpoint,
                geometries: geometries
            ),
        ]
            .compactMap { $0 }
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func sketchArcPathEndpoint(for reference: SketchReference) -> SketchArcPathEndpoint? {
        switch reference {
        case .arcStart(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: true)
        case .arcEnd(let entityID):
            return SketchArcPathEndpoint(entityID: entityID, isStart: false)
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius,
             .splineControlPoint:
            return nil
        }
    }

    private func sketchArcPathGeometry(
        entityID: SketchEntityID,
        arc: SketchArc,
        owner: String
    ) throws -> SketchArcPathGeometry {
        let center = try resolvedSketchPoint(arc.center, owner: "\(owner) arc center")
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let startAngle = try resolvedAngleValue(
            arc.startAngle,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngleValue(
            arc.endAngle,
            owner: "\(owner) arc end angle"
        )
        return SketchArcPathGeometry(
            entityID: entityID,
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            span: try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        )
    }

    private func sketchArcPathGeometry(
        _ geometry: SketchArcPathGeometry,
        matchesCircleOf seed: SketchArcPathGeometry
    ) -> Bool {
        nearlyEqual(geometry.center.x, seed.center.x, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.center.y, seed.center.y, tolerance: 1.0e-9) &&
            nearlyEqual(geometry.radius, seed.radius, tolerance: 1.0e-9)
    }

    private func connectedSketchArcSpanAngle(
        from start: SketchArcPathEndpoint,
        to target: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> Double? {
        func search(
            from current: SketchArcPathEndpoint,
            accumulatedSpan: Double,
            visitedArcs: Set<SketchEntityID>,
            visitedEndpoints: Set<SketchArcPathEndpoint>
        ) -> [Double] {
            if current == target {
                return [accumulatedSpan]
            }
            guard visitedEndpoints.contains(current) == false else {
                return []
            }
            let nextVisitedEndpoints = visitedEndpoints.union([current])
            var spans: [Double] = []
            if current.isStart,
               visitedArcs.contains(current.entityID) == false,
               let geometry = geometries[current.entityID] {
                spans.append(
                    contentsOf: search(
                        from: geometry.endEndpoint,
                        accumulatedSpan: accumulatedSpan + geometry.span,
                        visitedArcs: visitedArcs.union([current.entityID]),
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            for endpoint in matchingSketchArcPathEndpoints(
                current,
                geometries: geometries
            ) where endpoint != current {
                spans.append(
                    contentsOf: search(
                        from: endpoint,
                        accumulatedSpan: accumulatedSpan,
                        visitedArcs: visitedArcs,
                        visitedEndpoints: nextVisitedEndpoints
                    )
                )
            }
            return spans
        }
        let spans = search(
            from: start,
            accumulatedSpan: 0.0,
            visitedArcs: [],
            visitedEndpoints: []
        )
            .filter { $0 > 1.0e-12 }
        let uniqueSpans = uniqueSketchArcPathSpans(spans)
        guard uniqueSpans.count == 1 else {
            return nil
        }
        return uniqueSpans[0]
    }

    private func matchingSketchArcPathEndpoints(
        _ endpoint: SketchArcPathEndpoint,
        geometries: [SketchEntityID: SketchArcPathGeometry]
    ) -> [SketchArcPathEndpoint] {
        guard let source = geometries[endpoint.entityID] else {
            return []
        }
        let sourcePoint = sketchArcPathPoint(endpoint, geometry: source)
        return geometries.values.flatMap { geometry in
            [geometry.startEndpoint, geometry.endEndpoint].filter { candidate in
                let point = sketchArcPathPoint(candidate, geometry: geometry)
                return nearlyEqual(point.x, sourcePoint.x, tolerance: 1.0e-9) &&
                    nearlyEqual(point.y, sourcePoint.y, tolerance: 1.0e-9)
            }
        }
    }

    private func sketchArcPathPoint(
        _ endpoint: SketchArcPathEndpoint,
        geometry: SketchArcPathGeometry
    ) -> (x: Double, y: Double) {
        let angle = endpoint.isStart ? geometry.startAngle : geometry.endAngle
        return (
            x: geometry.center.x + cos(angle) * geometry.radius,
            y: geometry.center.y + sin(angle) * geometry.radius
        )
    }

    private func uniqueSketchArcPathSpans(_ spans: [Double]) -> [Double] {
        spans.reduce(into: []) { uniqueSpans, span in
            guard uniqueSpans.contains(where: { nearlyEqual($0, span, tolerance: 1.0e-9) }) == false else {
                return
            }
            uniqueSpans.append(span)
        }
    }

    private func measuredSketchCircularRadius(
        _ entityID: SketchEntityID,
        in sketch: Sketch,
        owner: String
    ) throws -> Double {
        guard let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing circular entity."
            )
        }
        switch entity {
        case .circle(let circle):
            return try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
        case .arc(let arc):
            return try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        case .point,
             .line,
             .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a circle or arc dimension target."
            )
        }
    }
}

private struct SketchArcPathEndpoint: Hashable {
    var entityID: SketchEntityID
    var isStart: Bool

    var reference: SketchReference {
        isStart ? .arcStart(entityID) : .arcEnd(entityID)
    }
}

private struct SketchArcPathGeometry {
    var entityID: SketchEntityID
    var center: (x: Double, y: Double)
    var radius: Double
    var startAngle: Double
    var endAngle: Double
    var span: Double

    var startEndpoint: SketchArcPathEndpoint {
        SketchArcPathEndpoint(entityID: entityID, isStart: true)
    }

    var endEndpoint: SketchArcPathEndpoint {
        SketchArcPathEndpoint(entityID: entityID, isStart: false)
    }
}
