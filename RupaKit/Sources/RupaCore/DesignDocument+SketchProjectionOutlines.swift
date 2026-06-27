import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func projectedOutlineSketchEntity(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity? {
        switch entry.curveKind {
        case "line":
            return try projectedOutlineLineEdge(
                entry,
                to: targetSystem,
                owner: owner
            )
        case "circle":
            return try projectedGeneratedCircularEdge(
                entry,
                to: targetSystem,
                owner: owner
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) currently supports outline projection for generated line and circular edges; B-spline or unknown edge outlines require exact trim-curve source support."
            )
        }
    }

    func projectedOutlineLineEdge(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity? {
        guard let start = entry.start,
              let end = entry.end else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) generated line edge has no resolved endpoints."
            )
        }
        let projectedStart = targetSystem.project(point3D(start)).point
        let projectedEnd = targetSystem.project(point3D(end)).point
        guard hypot(projectedEnd.x - projectedStart.x, projectedEnd.y - projectedStart.y) > 1.0e-12 else {
            return nil
        }
        return .line(SketchLine(
            start: sketchPoint(from: projectedStart),
            end: sketchPoint(from: projectedEnd)
        ))
    }

    func projectedSketchEntityKey(_ entity: SketchEntity) throws -> String {
        switch entity {
        case .line(let line):
            let start = try resolvedProjectionPoint(line.start, owner: "Projected outline line start")
            let end = try resolvedProjectionPoint(line.end, owner: "Projected outline line end")
            let first = quantizedPointKey(Point2D(x: start.x, y: start.y))
            let second = quantizedPointKey(Point2D(x: end.x, y: end.y))
            let endpoints = [first, second].sorted()
            return "line:\(endpoints[0]):\(endpoints[1])"
        case .circle(let circle):
            let center = try resolvedProjectionPoint(circle.center, owner: "Projected outline circle center")
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "Projected outline circle radius")
            return "circle:\(quantizedPointKey(Point2D(x: center.x, y: center.y))):\(quantizedValueKey(radius))"
        case .arc(let arc):
            let center = try resolvedProjectionPoint(arc.center, owner: "Projected outline arc center")
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "Projected outline arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "Projected outline arc start angle")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "Projected outline arc end angle")
            let start = Point2D(
                x: center.x + cos(startAngle) * radius,
                y: center.y + sin(startAngle) * radius
            )
            let end = Point2D(
                x: center.x + cos(endAngle) * radius,
                y: center.y + sin(endAngle) * radius
            )
            let endpoints = [quantizedPointKey(start), quantizedPointKey(end)].sorted()
            return "arc:\(quantizedPointKey(Point2D(x: center.x, y: center.y))):\(quantizedValueKey(radius)):\(endpoints[0]):\(endpoints[1])"
        case .spline:
            throw EditorError(
                code: .commandInvalid,
                message: "Project Outline cannot deduplicate spline outline curves yet."
            )
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "Project Outline cannot deduplicate point outline geometry."
            )
        }
    }

    func quantizedPointKey(_ point: Point2D) -> String {
        "\(quantizedValueKey(point.x)):\(quantizedValueKey(point.y))"
    }

    func quantizedValueKey(_ value: Double) -> String {
        let scale = 1.0e10
        return String(Int64((value * scale).rounded()))
    }
}
