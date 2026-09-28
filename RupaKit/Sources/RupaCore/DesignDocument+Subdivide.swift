import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Subdivide on a sketch spline: every nonempty knot span is split at its middle, so an n-span curve
    /// becomes 2n spans with the same shape. Returns the indices of the control points the splits
    /// created (each split's new joint and the handles beside it), which Subdivide selects.
    ///
    /// Constraints and dimensions on joints follow them; one on a span's inner handle, which the
    /// split moves, refuses the command with nothing changed.
    @discardableResult
    public mutating func subdivideSketchSpline(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> [Int] {
        let selection = try editableSketchEntity(for: target, operationName: "Subdivide")
        guard case .spline(let spline) = selection.entity else {
            throw EditorError(code: .commandInvalid, message: "Subdivide doubles the control points of a spline curve.")
        }
        let plan = try splineSubdivisionPlan(spline)
        let splineTarget = SelectionTarget(
            sceneNodeID: target.sceneNodeID,
            component: .sketchEntity(.sketchEntity(featureID: selection.featureID, entityID: selection.entityID))
        )

        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        for fraction in plan.fractions {
            try insertSketchSplineControlPoint(
                target: splineTarget, fraction: .scalar(fraction), objectRegistry: objectRegistry
            )
        }
        didCommit = true
        return plan.indices
    }

    /// The CV selection produced by the same refinement plan that Subdivide executes.
    public func sketchSplineSubdivisionControlPointIndices(_ spline: SketchSpline) throws -> [Int] {
        try splineSubdivisionPlan(spline).indices
    }

    private func splineSubdivisionPlan(_ spline: SketchSpline) throws -> (fractions: [Double], indices: [Int]) {
        try spline.validateForm()
        let degree = spline.degree
        var fractions: [Double] = []
        var joints: [Int] = []
        if var knots = spline.knots {
            let lower = knots[degree], upper = knots[knots.count - degree - 1]
            let midpoints = zip(knots, knots.dropFirst()).compactMap { a, b in a < b ? a + (b - a) / 2 : nil }
            fractions = midpoints.reversed().map { ($0 - lower) / (upper - lower) }
            for midpoint in midpoints {
                guard let index = knots.firstIndex(where: { $0 > midpoint }) else {
                    throw EditorError(code: .commandInvalid, message: "Subdivide could not resolve a knot span.")
                }
                knots.insert(contentsOf: repeatElement(midpoint, count: degree), at: index)
            }
            joints = try midpoints.map { midpoint in
                guard let index = knots.firstIndex(of: midpoint) else {
                    throw EditorError(code: .commandInvalid, message: "Subdivide lost an inserted knot.")
                }
                return index - 1
            }
        } else {
            guard let count = spline.spanCount else {
                throw EditorError(code: .commandInvalid, message: "Subdivide requires a valid spline.")
            }
            fractions = (0..<count).reversed().map { span in
                (Double(span) + 0.5) / Double(count + count - 1 - span)
            }
            joints = (0..<count).map { 2 * degree * $0 + degree }
        }
        let indices = joints.flatMap { joint in
            Array((joint - degree / 2)..<(joint - degree / 2 + degree))
        }
        return (fractions, indices)
    }

    /// Subdivide on a B-spline surface: its degree rises by one and it gains one span in each
    /// direction (a knot at the middle of the widest span), keeping its shape.
    public mutating func subdivideSurface(
        target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        switch target.component {
        case .object, .face: break
        default:
            throw EditorError(code: .commandInvalid, message: "Subdivide on a surface needs the surface or its face selected.")
        }
        guard let featureID = productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID,
              var feature = cadDocument.designGraph.nodes[featureID],
              case .bSplineSurface(var surfaceFeature) = feature.operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "Subdivide raises the degree of a B-spline surface; the selection is not one."
            )
        }
        let tolerance = modelingSettings.tolerance
        var surface = surfaceFeature.surface
        do {
            for direction in [SurfaceParameterDirection.u, .v] {
                surface = try surface.elevatingDegree(direction: direction, tolerance: tolerance)
                let knots = direction == .u ? surface.uKnots : surface.vKnots
                let degree = direction == .u ? surface.uDegree : surface.vDegree
                let spans = zip(knots[degree..<(knots.count - degree - 1)], knots[(degree + 1)...])
                    .filter { $0.1 > $0.0 }
                guard let widest = spans.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }) else { continue }
                surface = try surface.insertingKnot(
                    direction: direction, value: (widest.0 + widest.1) / 2, tolerance: tolerance
                )
            }
        } catch {
            throw EditorError(code: .commandInvalid, message: "Subdivide could not raise the surface: \(error).")
        }
        surfaceFeature.surface = surface
        try surfaceFeature.validate(tolerance: tolerance)
        feature.operation = .bSplineSurface(surfaceFeature)

        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        try cadDocument.replaceFeature(feature, tolerance: tolerance)
        for (id, node) in productMetadata.sceneNodes where node.reference?.featureID == featureID && node.object != nil {
            productMetadata.sceneNodes[id]?.object?.properties["surface.degree.u"] = .integer(surface.uDegree)
            productMetadata.sceneNodes[id]?.object?.properties["surface.degree.v"] = .integer(surface.vDegree)
            productMetadata.sceneNodes[id]?.object?.properties["control.point.u"] = .integer(surface.uControlPointCount)
            productMetadata.sceneNodes[id]?.object?.properties["control.point.v"] = .integer(surface.vControlPointCount)
        }
        try validate(objectRegistry: objectRegistry)
        didCommit = true
    }
}
