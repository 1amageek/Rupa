import SwiftCAD
import RupaCoreTypes

/// The lines and value of a distance dimension between two points, measured along an axis or
/// straight, with its dimension line through a label position.
public struct MeasurementDimensionGeometry: Equatable, Sendable {
    public let start: Point3D
    public let end: Point3D
    public let dimensionStart: Point3D
    public let dimensionEnd: Point3D
    public let labelAnchor: Point3D
    public let valueMeters: Double

    public init(start: Point3D, end: Point3D, axis: Vector3D?, labelPosition: Point3D?) throws {
        let span = end - start
        guard span.length > 1.0e-12 else {
            throw EditorError(code: .commandInvalid, message: "A distance needs two different points.")
        }
        let direction = try (axis ?? span).normalized(tolerance: 1.0e-12)
        let midpoint = start + span * 0.5
        let label = labelPosition ?? midpoint
        self.start = start
        self.end = end
        if axis == nil {
            // The dimension line runs parallel to the points, offset to pass through the label.
            let offset = (label - start) - direction * (label - start).dot(direction)
            dimensionStart = start + offset
            dimensionEnd = end + offset
            valueMeters = span.length
        } else {
            dimensionStart = label + direction * (start - label).dot(direction)
            dimensionEnd = label + direction * (end - label).dot(direction)
            valueMeters = abs(span.dot(direction))
        }
        labelAnchor = dimensionStart + (dimensionEnd - dimensionStart) * 0.5
    }

    /// The lines from each point to its end of the dimension line, leaving out any that vanish.
    public var extensionLines: [[Point3D]] {
        [[start, dimensionStart], [end, dimensionEnd]].filter { ($0[1] - $0[0]).length > 1.0e-12 }
    }

    /// The construction-plane axis a dimension measures along for a cursor at `cursor`: the one
    /// most perpendicular on screen to the cursor's offset from the midpoint, among the axes along
    /// which the points differ and that are not seen end-on; `nil` (straight) when there is none.
    public static func placementAxis(
        start: Point3D,
        end: Point3D,
        cursor: Point3D,
        viewNormal: Vector3D,
        planeAxes: [Vector3D]
    ) -> Vector3D? {
        let span = end - start
        let view: Vector3D
        do {
            view = try viewNormal.normalized(tolerance: 1.0e-12)
        } catch {
            return nil
        }
        let midpoint = start + span * 0.5
        let rawOffset = cursor - midpoint
        let offset = rawOffset - view * rawOffset.dot(view)
        var best: (axis: Vector3D, score: Double)?
        for axis in planeAxes {
            guard let unit = try? axis.normalized(tolerance: 1.0e-12),
                  abs(span.dot(unit)) > 1.0e-9 * max(span.length, 1.0e-9) else { continue }
            let onScreen = unit - view * unit.dot(view)
            guard onScreen.length > 0.2 else { continue }
            let score: Double
            if offset.length > 1.0e-12 {
                score = abs(offset.dot(onScreen) / (offset.length * onScreen.length))
            } else {
                // With the cursor on the midpoint, prefer the axis the points differ most along.
                score = -abs(span.dot(unit))
            }
            if best == nil || score < best!.score {
                best = (unit, score)
            }
        }
        return best?.axis
    }
}
