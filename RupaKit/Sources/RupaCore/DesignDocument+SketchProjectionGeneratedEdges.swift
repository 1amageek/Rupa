import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func projectedGeneratedEdgeSketchEntity(
        for target: SelectionTarget,
        targetSystem: SketchPlaneCoordinateSystem,
        operationName: String,
        objectRegistry: ObjectTypeRegistry,
        topology: inout TopologySnapshot?
    ) throws -> SketchEntity {
        guard case .edge(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated projection requires a generated edge target."
            )
        }
        if topology == nil {
            topology = try TopologySnapshotService().snapshot(
                document: self,
                objectRegistry: objectRegistry
            )
        }
        guard let topology else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated edge projection could not evaluate topology."
            )
        }
        guard let entry = topology.entries.first(where: { $0.persistentName == persistentName }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(operationName) generated edge target was not found in the current evaluation."
            )
        }
        guard entry.kind == .edge,
              entry.sceneNodeID == target.sceneNodeID.description else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) generated edge target must reference an edge on the selected body."
            )
        }
        switch entry.curveKind {
        case "line":
            return try projectedGeneratedLineEdge(
                entry,
                to: targetSystem,
                owner: operationName
            )
        case "circle":
            return try projectedGeneratedCircularEdge(
                entry,
                to: targetSystem,
                owner: operationName
            )
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) currently supports generated line and circular edge targets; B-spline or unknown generated edge projection requires exact trim-curve source support."
            )
        }
    }

    func projectedGeneratedLineEdge(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity {
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
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) projected generated edge collapsed on the target construction plane."
            )
        }
        return .line(SketchLine(
            start: sketchPoint(from: projectedStart),
            end: sketchPoint(from: projectedEnd)
        ))
    }

    func projectedGeneratedCircularEdge(
        _ entry: TopologySummaryResult.Entry,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity {
        guard let center = entry.curveCenter,
              let normal = entry.curveNormal,
              let xAxis = entry.curveParameterXAxis,
              let yAxis = entry.curveParameterYAxis,
              let radius = entry.curveRadius,
              let range = entry.edgeParameterRange,
              radius.isFinite,
              radius > 1.0e-12,
              range.start.isFinite,
              range.end.isFinite else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) generated circular edge has incomplete curve parameters."
            )
        }
        let circularNormal = try vector3D(normal).normalized(tolerance: 1.0e-12)
        guard abs(abs(circularNormal.dot(targetSystem.normal)) - 1.0) <= 1.0e-9 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) can project circular generated edges only onto a parallel construction plane until ellipse or exact conic projection sources exist."
            )
        }
        let projectedCenter = targetSystem.project(point3D(center)).point
        let span = range.end - range.start
        guard abs(span) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) generated circular edge has a collapsed trim range."
            )
        }
        if abs(abs(span) - Double.pi * 2.0) <= 1.0e-7 {
            return .circle(SketchCircle(
                center: sketchPoint(from: projectedCenter),
                radius: .length(radius, .meter)
            ))
        }
        let sourceStart = try circularEdgeWorldPoint(
            center: center,
            xAxis: xAxis,
            yAxis: yAxis,
            radius: radius,
            parameter: range.start,
            owner: owner
        )
        let sourceEnd = try circularEdgeWorldPoint(
            center: center,
            xAxis: xAxis,
            yAxis: yAxis,
            radius: radius,
            parameter: range.end,
            owner: owner
        )
        let sourceMid = try circularEdgeWorldPoint(
            center: center,
            xAxis: xAxis,
            yAxis: yAxis,
            radius: radius,
            parameter: range.start + span / 2.0,
            owner: owner
        )
        let projectedStart = targetSystem.project(sourceStart).point
        let projectedEnd = targetSystem.project(sourceEnd).point
        let projectedMid = targetSystem.project(sourceMid).point
        let startAngle = atan2(projectedStart.y - projectedCenter.y, projectedStart.x - projectedCenter.x)
        let endAngle = atan2(projectedEnd.y - projectedCenter.y, projectedEnd.x - projectedCenter.x)
        let directDistance = projectedArcMidpointDistance(
            center: projectedCenter,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            expected: projectedMid
        )
        let reversedDistance = projectedArcMidpointDistance(
            center: projectedCenter,
            radius: radius,
            startAngle: endAngle,
            endAngle: startAngle,
            expected: projectedMid
        )
        if reversedDistance < directDistance {
            return .arc(SketchArc(
                center: sketchPoint(from: projectedCenter),
                radius: .length(radius, .meter),
                startAngle: .angle(endAngle, .radian),
                endAngle: .angle(startAngle, .radian)
            ))
        }
        return .arc(SketchArc(
            center: sketchPoint(from: projectedCenter),
            radius: .length(radius, .meter),
            startAngle: .angle(startAngle, .radian),
            endAngle: .angle(endAngle, .radian)
        ))
    }
}
