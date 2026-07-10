import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func projectedSketchEntity(
        for target: SelectionTarget,
        targetSystem: SketchPlaneCoordinateSystem,
        operationName: String,
        objectRegistry: ObjectTypeRegistry,
        topology: inout TopologySnapshot?
    ) throws -> (entity: SketchEntity, sourceName: String) {
        if case .sketchEntity = target.component {
            let selection = try editableSketchEntity(
                for: target,
                operationName: "\(operationName) source"
            )
            let sourceSystem = try SketchPlaneCoordinateSystem(plane: selection.sketch.plane)
            return (
                entity: try projectedSketchEntity(
                    selection.entity,
                    from: sourceSystem,
                    to: targetSystem,
                    owner: operationName
                ),
                sourceName: selection.feature.name ?? "Sketch Curve"
            )
        }
        if case .edge(let componentID) = target.component,
           componentID.generatedTopologyPersistentName != nil {
            return (
                entity: try projectedGeneratedEdgeSketchEntity(
                    for: target,
                    targetSystem: targetSystem,
                    operationName: operationName,
                    objectRegistry: objectRegistry,
                    topology: &topology
                ),
                sourceName: "Generated Edge"
            )
        }
        throw EditorError(
            code: .commandInvalid,
            message: "\(operationName) requires source sketch curve or generated edge targets."
        )
    }

    func projectedSketchEntity(
        _ entity: SketchEntity,
        from sourceSystem: SketchPlaneCoordinateSystem,
        to targetSystem: SketchPlaneCoordinateSystem,
        owner: String
    ) throws -> SketchEntity {
        switch entity {
        case .point:
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires curve entities, not source point entities."
            )
        case .line(let line):
            let start = try projectedSketchPoint(
                line.start,
                from: sourceSystem,
                to: targetSystem,
                owner: "\(owner) line start"
            )
            let end = try projectedSketchPoint(
                line.end,
                from: sourceSystem,
                to: targetSystem,
                owner: "\(owner) line end"
            )
            let startPoint = try resolvedProjectionPoint(start, owner: "\(owner) projected line start")
            let endPoint = try resolvedProjectionPoint(end, owner: "\(owner) projected line end")
            guard hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) > 1.0e-12 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) projected line collapsed on the target construction plane."
                )
            }
            return .line(SketchLine(start: start, end: end))
        case .circle(let circle):
            try validateCircularProjection(
                from: sourceSystem,
                to: targetSystem,
                owner: owner
            )
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
            return .circle(SketchCircle(
                center: try projectedSketchPoint(
                    circle.center,
                    from: sourceSystem,
                    to: targetSystem,
                    owner: "\(owner) circle center"
                ),
                radius: .length(radius, .meter)
            ))
        case .arc(let arc):
            try validateCircularProjection(
                from: sourceSystem,
                to: targetSystem,
                owner: owner
            )
            return .arc(try projectedSketchArc(
                arc,
                from: sourceSystem,
                to: targetSystem,
                owner: owner
            ))
        case .spline(let spline):
            return .spline(SketchSpline(
                controlPoints: try spline.controlPoints.enumerated().map { index, point in
                    try projectedSketchPoint(
                        point,
                        from: sourceSystem,
                        to: targetSystem,
                        owner: "\(owner) spline control point \(index)"
                    )
                }
            ))
        }
    }
}
