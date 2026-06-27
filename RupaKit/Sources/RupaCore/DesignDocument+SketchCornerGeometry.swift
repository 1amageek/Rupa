import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    struct SketchCornerEndpointGeometry {
        var endpoint: SketchCurveEndpoint
        var entity: SketchEntity
        var vertex: SketchCornerPoint
        var length: Double
        var unit: SketchCornerPoint
        var arc: SketchCornerArcGeometry?
    }

    struct SketchCornerArcGeometry {
        var center: SketchCornerPoint
        var radius: Double
        var startAngle: Double
        var endAngle: Double
        var span: Double

        func point(atDistanceFromEndpoint distance: Double, endpoint: ArcEndpoint) -> SketchCornerPoint {
            let angle = endpoint.isStart
                ? startAngle + distance / radius
                : endAngle - distance / radius
            return point(atStorageAngle: angle)
        }

        func point(atStorageAngle angle: Double) -> SketchCornerPoint {
            SketchCornerPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }

        func storageAngle(
            for point: SketchCornerPoint,
            owner: String,
            tolerance: Double
        ) throws -> Double {
            let radialDistance = center.distance(to: point)
            guard abs(radialDistance - radius) <= max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a point outside the source arc."
                )
            }
            let rawAngle = atan2(point.y - center.y, point.x - center.x)
            let offset = nonnegativeAngleSpan(
                from: startAngle,
                to: rawAngle
            )
            guard offset >= -tolerance,
                  offset <= span + max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a point outside the source arc span."
                )
            }
            return startAngle + min(max(offset, 0.0), span)
        }

        func pathDistanceFromEndpoint(
            to point: SketchCornerPoint,
            endpoint: ArcEndpoint,
            owner: String,
            tolerance: Double
        ) throws -> Double {
            let angle = try storageAngle(for: point, owner: owner, tolerance: tolerance)
            let spanFromEndpoint = endpoint.isStart
                ? angle - startAngle
                : endAngle - angle
            let distance = max(0.0, min(spanFromEndpoint, span)) * radius
            guard distance <= radius * span + max(tolerance, radius * 1.0e-8) else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) produced a point outside the source arc span."
                )
            }
            return distance
        }

        private func nonnegativeAngleSpan(
            from startAngle: Double,
            to endAngle: Double
        ) -> Double {
            let fullCircle = Double.pi * 2.0
            var span = endAngle - startAngle
            while span < 0.0 {
                span += fullCircle
            }
            while span > fullCircle {
                span -= fullCircle
            }
            return span
        }
    }

    struct SketchCornerPoint: Equatable, Sendable {
        var x: Double
        var y: Double

        var leftNormal: SketchCornerPoint {
            SketchCornerPoint(x: -y, y: x)
        }

        func adding(_ other: SketchCornerPoint) -> SketchCornerPoint {
            SketchCornerPoint(x: x + other.x, y: y + other.y)
        }

        func subtracting(_ other: SketchCornerPoint) -> SketchCornerPoint {
            SketchCornerPoint(x: x - other.x, y: y - other.y)
        }

        func scaled(by scale: Double) -> SketchCornerPoint {
            SketchCornerPoint(x: x * scale, y: y * scale)
        }

        func dot(_ other: SketchCornerPoint) -> Double {
            x * other.x + y * other.y
        }

        func cross(_ other: SketchCornerPoint) -> Double {
            x * other.y - y * other.x
        }

        func distance(to other: SketchCornerPoint) -> Double {
            hypot(x - other.x, y - other.y)
        }

        func normalized(owner: String, tolerance: Double) throws -> SketchCornerPoint {
            let length = hypot(x, y)
            guard length > tolerance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a stable direction."
                )
            }
            return scaled(by: 1.0 / length)
        }
    }

    func sketchCornerEndpointGeometry(
        _ entity: SketchEntity,
        endpoint: SketchCurveEndpoint,
        owner: String
    ) throws -> SketchCornerEndpointGeometry {
        switch (entity, endpoint) {
        case (.line(let line), .line(let lineEndpoint)):
            let vertex = try resolvedSketchCornerPoint(
                lineEndpoint.isStart ? line.start : line.end,
                owner: "\(owner) vertex"
            )
            let far = try resolvedSketchCornerPoint(
                lineEndpoint.isStart ? line.end : line.start,
                owner: "\(owner) far point"
            )
            let vertexPoint = SketchCornerPoint(x: vertex.x, y: vertex.y)
            let farPoint = SketchCornerPoint(x: far.x, y: far.y)
            let delta = farPoint.subtracting(vertexPoint)
            let length = vertexPoint.distance(to: farPoint)
            guard length > ModelingTolerance.standard.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) requires a line with non-zero length."
                )
            }
            return SketchCornerEndpointGeometry(
                endpoint: endpoint,
                entity: entity,
                vertex: vertexPoint,
                length: length,
                unit: delta.scaled(by: 1.0 / length),
                arc: nil
            )
        case (.arc(let arc), .arc(let arcEndpoint)):
            let center = try resolvedSketchCornerPoint(arc.center, owner: "\(owner) center")
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "\(owner) end angle")
            let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
            let endpointAngle = arcEndpoint.isStart ? startAngle : endAngle
            let vertex = SketchCornerPoint(
                x: center.x + cos(endpointAngle) * radius,
                y: center.y + sin(endpointAngle) * radius
            )
            let unit = arcEndpoint.isStart
                ? SketchCornerPoint(x: -sin(endpointAngle), y: cos(endpointAngle))
                : SketchCornerPoint(x: sin(endpointAngle), y: -cos(endpointAngle))
            return SketchCornerEndpointGeometry(
                endpoint: endpoint,
                entity: entity,
                vertex: vertex,
                length: radius * span,
                unit: unit,
                arc: SketchCornerArcGeometry(
                    center: SketchCornerPoint(x: center.x, y: center.y),
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: startAngle + span,
                    span: span
                )
            )
        case (.point, _),
             (.circle, _),
             (.spline, _),
             (.line, .arc),
             (.arc, .line):
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) endpoint target does not match the selected curve type."
            )
        }
    }

    func sketchCornerTreatmentPoint(
        from geometry: SketchCornerEndpointGeometry,
        distance: Double
    ) throws -> SketchCornerPoint {
        try validateSketchCornerTrimDistance(
            distance,
            selectedGeometry: geometry,
            adjacentGeometry: nil
        )
        if let arc = geometry.arc,
           case .arc(let endpoint) = geometry.endpoint {
            return arc.point(atDistanceFromEndpoint: distance, endpoint: endpoint)
        }
        return geometry.vertex.adding(geometry.unit.scaled(by: distance))
    }
    func validateSketchCornerTrimDistance(
        _ distance: Double,
        selectedGeometry: SketchCornerEndpointGeometry,
        adjacentGeometry: SketchCornerEndpointGeometry?
    ) throws {
        guard distance.isFinite,
              distance > ModelingTolerance.standard.distance,
              selectedGeometry.length - distance > ModelingTolerance.standard.distance,
              adjacentGeometry.map({ $0.length - distance > ModelingTolerance.standard.distance }) ?? true else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch corner treatment distance would collapse one of the adjacent curve sides."
            )
        }
    }

    func sketchCornerPathDistance(
        fromEndpointOf geometry: SketchCornerEndpointGeometry,
        to point: SketchCornerPoint,
        owner: String,
        tolerance: Double
    ) throws -> Double {
        if let arc = geometry.arc,
           case .arc(let endpoint) = geometry.endpoint {
            return try arc.pathDistanceFromEndpoint(
                to: point,
                endpoint: endpoint,
                owner: owner,
                tolerance: tolerance
            )
        }
        let pointVector = point.subtracting(geometry.vertex)
        let cross = abs(pointVector.cross(geometry.unit))
        guard cross <= max(tolerance, geometry.length * tolerance) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced a point outside the source line."
            )
        }
        let distance = pointVector.dot(geometry.unit)
        guard distance >= -tolerance,
              distance <= geometry.length + tolerance else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) produced a point outside the source line."
            )
        }
        return min(max(distance, 0.0), geometry.length)
    }

    func lineBySettingEndpoint(
        _ line: SketchLine,
        endpoint: LineEndpoint,
        point: SketchPoint
    ) -> SketchLine {
        if endpoint.isStart {
            return SketchLine(start: point, end: line.end)
        }
        return SketchLine(start: line.start, end: point)
    }

    func literalSketchPoint(_ point: SketchCornerPoint) -> SketchPoint {
        literalSketchPoint(x: point.x, y: point.y)
    }

    func literalSketchPoint(x: Double, y: Double) -> SketchPoint {
        SketchPoint(
            x: .length(x, .meter),
            y: .length(y, .meter)
        )
    }

    private func resolvedSketchCornerPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }
}
