import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Split Segment: inserts a vertex into a sketch line, arc or open spline at the curve point
    /// nearest `point`, in the sketch's plane coordinates, dividing it into two segments. The
    /// point is Swift-CAD's projection onto the curve.
    @discardableResult
    public mutating func splitSketchCurve(
        target: SelectionTarget,
        at point: Point2D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntityID {
        let selection = try editableSketchEntity(for: target, operationName: "Split Segment")
        if case .circle = selection.entity {
            throw EditorError(code: .commandInvalid, message: "Split Segment takes a line, arc or open spline.")
        }
        let fraction = try sketchCurveSplitParameter(of: selection.entity, nearestTo: point)
        return try splitSketchCurve(target: target, fraction: .scalar(fraction), objectRegistry: objectRegistry)
    }
}
