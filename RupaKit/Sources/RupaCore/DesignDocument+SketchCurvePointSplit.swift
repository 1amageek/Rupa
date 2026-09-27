import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Split Segment: inserts a vertex into a sketch line, arc or open spline at the curve point
    /// nearest `point`, in the sketch's plane coordinates, dividing it into two segments; a closed
    /// spline opens there instead (`openClosedSketchSpline`) and its own entity is returned. The
    /// point is Swift-CAD's projection onto the curve.
    @discardableResult
    public mutating func splitSketchCurve(
        target: SelectionTarget,
        at point: Point2D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let selection = try editableSketchEntity(for: target, operationName: "Split Segment")
        if case .circle = selection.entity {
            // A circle has no seam to put a vertex at in the sketch model.
            throw EditorError(code: .commandInvalid, message: "Split Segment takes a line, arc or spline; a circle has no seam to split at.")
        }
        if case .spline(let spline) = selection.entity, spline.isClosed {
            try openClosedSketchSpline(selection, spline: spline, at: point, objectRegistry: objectRegistry)
            return selection.entityID
        }
        let fraction = try sketchCurveSplitParameter(of: selection.entity, nearestTo: point)
        return try splitSketchCurve(target: target, fraction: .scalar(fraction), objectRegistry: objectRegistry)
    }

    /// Insert Knot: inserts a control point into an open spline at its point nearest `point`, in the
    /// sketch's plane coordinates, keeping the curve's shape. Returns the new control point's index.
    @discardableResult
    public mutating func insertSketchSplineControlPoint(
        target: SelectionTarget,
        at point: Point2D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> Int {
        let selection = try editableSketchEntity(for: target, operationName: "Insert Knot")
        guard case .spline = selection.entity else {
            throw EditorError(code: .commandInvalid, message: "Insert Knot takes a spline.")
        }
        let fraction = try sketchCurveSplitParameter(of: selection.entity, nearestTo: point)
        return try insertSketchSplineControlPoint(target: target, fraction: .scalar(fraction), objectRegistry: objectRegistry)
    }
}
