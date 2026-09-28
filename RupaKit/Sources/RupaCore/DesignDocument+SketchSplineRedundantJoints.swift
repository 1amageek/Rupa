import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Delete Redundant Topology on a sketch spline: removes every joint whose two spans are the
    /// halves of one cubic, from the last joint back, so the curve keeps its shape with fewer
    /// control points. Swift-CAD's `CubicBezierChainJoints` decides each joint. A joint whose three
    /// control points a constraint or dimension names is kept; references past a removed joint move
    /// back three indices. Returns how many joints were removed; a spline with none is refused.
    @discardableResult
    public mutating func deleteRedundantSketchSplineJoints(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> Int {
        let selection = try editableSketchEntity(for: target, operationName: "Delete Redundant Topology")
        guard case .spline(var spline) = selection.entity, !spline.isClosed else {
            throw EditorError(code: .commandInvalid, message: "Delete Redundant Topology takes an open spline.")
        }
        guard productMetadata.bridgeCurveSources.values.contains(where: { source in
            source.featureID == selection.featureID && source.entityID == selection.entityID
        }) == false else {
            throw EditorError(code: .commandInvalid, message: "Delete Redundant Topology cannot edit a generated Bridge Curve.")
        }
        var points = try spline.controlPoints.map { point -> Point2D in
            let resolved = try resolvedSketchPoint(point, owner: "Delete Redundant Topology control point")
            return Point2D(x: resolved.x, y: resolved.y)
        }
        var sketch = selection.sketch
        let joints = CubicBezierChainJoints(tolerance: .standard)
        var removed = 0
        var joint = (points.count - 1) / 3 - 1
        while joint >= 1 {
            let affected = [3 * joint - 1, 3 * joint, 3 * joint + 1]
            let merged: [Point2D]?
            do {
                merged = try joints.mergedSpan(of: points, atJoint: joint)
            } catch let error as KernelError {
                throw EditorError(code: .commandInvalid, message: "Delete Redundant Topology: \(error.message)")
            }
            if !affected.contains(where: { sketch.namesSplineControlPoint(entity: selection.entityID, index: $0) }),
               let merged {
                let span = (3 * joint - 3)...(3 * joint + 3)
                points.replaceSubrange(span, with: merged)
                spline.controlPoints.replaceSubrange(span, with: [
                    spline.controlPoints[span.lowerBound],
                    sketchPoint(x: merged[1].x, y: merged[1].y),
                    sketchPoint(x: merged[2].x, y: merged[2].y),
                    spline.controlPoints[span.upperBound],
                ])
                let removedAfter = 3 * joint + 1
                sketch.remapSplineControlPoints(entity: selection.entityID) { $0 > removedAfter ? $0 - 3 : $0 }
                removed += 1
            }
            joint -= 1
        }
        guard removed > 0 else {
            throw EditorError(code: .commandInvalid, message: "The spline has no joint that one cubic spans.")
        }
        var feature = selection.feature
        sketch.entities[selection.entityID] = .spline(spline)
        try validateCubicBezierChainSpline(spline, owner: "Delete Redundant Topology")
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Delete Redundant Topology"
        )
        return removed
    }
}

extension Sketch {
    /// Whether a constraint or dimension names control point `index` of spline `entity`.
    func namesSplineControlPoint(entity: SketchEntityID, index: Int) -> Bool {
        func names(_ reference: SketchReference) -> Bool {
            if case .splineControlPoint(entity, index) = reference { return true }
            return false
        }
        let constrained = constraints.contains { constraint in
            switch constraint {
            case .coincident(let first, let second): names(first) || names(second)
            case .fixed(let reference): names(reference)
            case .smoothSplineControlPoint(let id, let controlPoint): id == entity && controlPoint == index
            default: false
            }
        }
        let dimensioned = dimensions.contains { dimension in
            switch dimension {
            case .distance(let from, let to, _), .angle(let from, let to, _): names(from) || names(to)
            case .radius, .diameter: false
            }
        }
        return constrained || dimensioned
    }

    /// Renumbers every reference to a control point of spline `entity` through `map`.
    mutating func remapSplineControlPoints(entity: SketchEntityID, _ map: (Int) -> Int) {
        func remapped(_ reference: SketchReference) -> SketchReference {
            if case .splineControlPoint(entity, let index) = reference {
                return .splineControlPoint(entity: entity, index: map(index))
            }
            return reference
        }
        constraints = constraints.map { constraint in
            switch constraint {
            case .coincident(let first, let second): .coincident(remapped(first), remapped(second))
            case .fixed(let reference): .fixed(remapped(reference))
            case .smoothSplineControlPoint(let id, let index) where id == entity:
                .smoothSplineControlPoint(entity: id, index: map(index))
            default: constraint
            }
        }
        dimensions = dimensions.map { dimension in
            switch dimension {
            case .distance(let from, let to, let value): .distance(from: remapped(from), to: remapped(to), value: value)
            case .angle(let from, let to, let value): .angle(from: remapped(from), to: remapped(to), value: value)
            case .radius, .diameter: dimension
            }
        }
    }
}
