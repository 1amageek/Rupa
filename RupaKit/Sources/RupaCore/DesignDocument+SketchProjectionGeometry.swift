import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func validateCircularProjection(
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws {
        guard sourceSystem.projectsParallel(to: targetSystem) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) can project circle and arc sources only onto a parallel construction plane until ellipse or exact conic projection sources exist."
            )
        }
    }

    func projectedSketchArc(
        _ arc: SketchArc,
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchArc {
        let resolvedCenter = try resolvedProjectionPoint(arc.center, owner: "\(owner) arc center")
        let sourceCenter = Point2D(x: resolvedCenter.x, y: resolvedCenter.y)
        let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
        let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
        let span = try normalizedPartialArcSpan(
            startAngle: startAngle,
            endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
        )
        let endAngle = startAngle + span
        let sourceStart = Point2D(
            x: sourceCenter.x + cos(startAngle) * radius,
            y: sourceCenter.y + sin(startAngle) * radius
        )
        let sourceEnd = Point2D(
            x: sourceCenter.x + cos(endAngle) * radius,
            y: sourceCenter.y + sin(endAngle) * radius
        )
        let sourceMid = Point2D(
            x: sourceCenter.x + cos(startAngle + span / 2.0) * radius,
            y: sourceCenter.y + sin(startAngle + span / 2.0) * radius
        )
        let center = targetSystem.project(sourceSystem.point(from: sourceCenter)).point
        let projectedStart = targetSystem.project(sourceSystem.point(from: sourceStart)).point
        let projectedEnd = targetSystem.project(sourceSystem.point(from: sourceEnd)).point
        let projectedMid = targetSystem.project(sourceSystem.point(from: sourceMid)).point
        let targetStartAngle = atan2(projectedStart.y - center.y, projectedStart.x - center.x)
        let targetEndAngle = atan2(projectedEnd.y - center.y, projectedEnd.x - center.x)
        let directDistance = projectedArcMidpointDistance(
            center: center,
            radius: radius,
            startAngle: targetStartAngle,
            endAngle: targetEndAngle,
            expected: projectedMid
        )
        let reversedDistance = projectedArcMidpointDistance(
            center: center,
            radius: radius,
            startAngle: targetEndAngle,
            endAngle: targetStartAngle,
            expected: projectedMid
        )
        if reversedDistance < directDistance {
            return SketchArc(
                center: sketchPoint(from: center),
                radius: .length(radius, .meter),
                startAngle: .angle(targetEndAngle, .radian),
                endAngle: .angle(targetStartAngle, .radian)
            )
        }
        return SketchArc(
            center: sketchPoint(from: center),
            radius: .length(radius, .meter),
            startAngle: .angle(targetStartAngle, .radian),
            endAngle: .angle(targetEndAngle, .radian)
        )
    }

    func projectedArcMidpointDistance(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        expected: Point2D
    ) -> Double {
        let span = (endAngle - startAngle).truncatingRemainder(dividingBy: Double.pi * 2.0)
        let positiveSpan = span > 0.0 ? span : span + Double.pi * 2.0
        let midpointAngle = startAngle + positiveSpan / 2.0
        let midpoint = Point2D(
            x: center.x + cos(midpointAngle) * radius,
            y: center.y + sin(midpointAngle) * radius
        )
        return hypot(midpoint.x - expected.x, midpoint.y - expected.y)
    }

    func projectedSketchPoint(
        _ point: SketchPoint,
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchPoint {
        let sourcePoint = try resolvedProjectionPoint(point, owner: owner)
        let projected = targetSystem.project(
            sourceSystem.point(from: Point2D(x: sourcePoint.x, y: sourcePoint.y))
        ).point
        return sketchPoint(from: projected)
    }

    func resolvedProjectionPoint(
        _ point: SketchPoint,
        owner: String
    ) throws -> (x: Double, y: Double) {
        (
            x: try resolvedLengthValue(point.x, owner: "\(owner) x"),
            y: try resolvedLengthValue(point.y, owner: "\(owner) y")
        )
    }

    func sketchPoint(from point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .length(point.x, .meter),
            y: .length(point.y, .meter)
        )
    }

    func circularEdgeWorldPoint(
        center: TopologySummaryResult.Entry.Point,
        xAxis: TopologySummaryResult.Entry.Point,
        yAxis: TopologySummaryResult.Entry.Point,
        radius: Double,
        parameter: Double,
        owner: String
    ) throws -> Point3D {
        guard parameter.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) generated circular edge has a non-finite trim parameter."
            )
        }
        let cosine = cos(parameter)
        let sine = sin(parameter)
        return Point3D(
            x: center.x + (xAxis.x * cosine + yAxis.x * sine) * radius,
            y: center.y + (xAxis.y * cosine + yAxis.y * sine) * radius,
            z: center.z + (xAxis.z * cosine + yAxis.z * sine) * radius
        )
    }

    func point3D(_ point: TopologySummaryResult.Entry.Point) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }

    func vector3D(_ point: TopologySummaryResult.Entry.Point) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}
