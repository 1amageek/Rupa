import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Translates a body in its profile-sketch plane by rewriting every entity
    /// of the profile sketch. The whole-sketch translation preserves all
    /// relative constraints and dimensions; sketches pinned by a fixed
    /// constraint are rejected because moving them would contradict the pin.
    public mutating func moveBody(
        target: SelectionTarget,
        deltaX: CADExpression,
        deltaY: CADExpression,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let deltaXMeters = try resolvedLengthValue(deltaX, owner: "Body move delta X")
        let deltaYMeters = try resolvedLengthValue(deltaY, owner: "Body move delta Y")
        guard abs(deltaXMeters) > 1.0e-12 || abs(deltaYMeters) > 1.0e-12 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Body move delta must not be zero."
            )
        }
        let resolvedTarget = try editableBodyTargetResolution(
            for: target,
            operationName: "Body move"
        )
        guard let bodyNode = cadDocument.designGraph.nodes[resolvedTarget.featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Body move could not resolve the body feature."
            )
        }
        guard case .extrude(let extrudeFeature) = bodyNode.operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Body move currently supports extruded bodies; other feature kinds are not movable yet."
            )
        }
        let sketchFeatureID = extrudeFeature.profile.featureID
        guard var sketchFeature = cadDocument.designGraph.nodes[sketchFeatureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Body move could not resolve the profile sketch feature."
            )
        }
        guard case .sketch(var sketch) = sketchFeature.operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Body move requires a sketch-backed profile."
            )
        }
        for constraint in sketch.constraints {
            if case .fixed = constraint {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Body move cannot translate a profile sketch pinned by a fixed constraint."
                )
            }
        }

        for (entityID, entity) in sketch.entities {
            sketch.entities[entityID] = translatedBodyMoveEntity(
                entity,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaXMeters: deltaXMeters,
                deltaYMeters: deltaYMeters
            )
        }

        try commitSketchEntityEdit(
            featureID: sketchFeatureID,
            feature: &sketchFeature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Body move"
        )
    }

    private func translatedBodyMoveEntity(
        _ entity: SketchEntity,
        deltaX: CADExpression,
        deltaY: CADExpression,
        deltaXMeters: Double,
        deltaYMeters: Double
    ) -> SketchEntity {
        func moved(_ point: SketchPoint) -> SketchPoint {
            translatedSketchPoint(
                point,
                deltaX: deltaX,
                deltaY: deltaY,
                deltaXMeters: deltaXMeters,
                deltaYMeters: deltaYMeters
            )
        }
        switch entity {
        case .point(let point):
            return .point(moved(point))
        case .line(var line):
            line.start = moved(line.start)
            line.end = moved(line.end)
            return .line(line)
        case .circle(var circle):
            circle.center = moved(circle.center)
            return .circle(circle)
        case .arc(var arc):
            arc.center = moved(arc.center)
            return .arc(arc)
        case .spline(var spline):
            spline.controlPoints = spline.controlPoints.map(moved)
            return .spline(spline)
        }
    }
}
