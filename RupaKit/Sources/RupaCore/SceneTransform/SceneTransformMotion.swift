import Foundation
import SwiftCAD
import RupaCoreTypes

/// The world-space motions Move, Rotate and Scale produce, each stated in a transform frame or by
/// freestyle points.
public enum SceneTransformMotion {
    /// A move by frame components: one axis, a plane (two components) or all three.
    public static func translation(in frame: SceneTransformFrame, by components: Vector3D) throws -> Transform3D {
        try Transform3D.translation(frame.worldVector(components))
    }

    /// A turn by `angleRadians` about a frame axis through the pivot.
    public static func rotation(
        in frame: SceneTransformFrame,
        about axis: SceneTransformAxis,
        angleRadians: Double
    ) throws -> Transform3D {
        try Transform3D.rotation(axis: frame.axis(axis), angleRadians: angleRadians, about: frame.origin)
    }

    /// A scale by one factor per frame axis about the pivot.
    public static func scale(in frame: SceneTransformFrame, factors: Vector3D) throws -> Transform3D {
        for factor in [factors.x, factors.y, factors.z] {
            guard factor.isFinite, abs(factor) > ModelingTolerance.standard.relative else {
                throw EditorError(code: .commandInvalid, message: "A scale factor must be finite and not collapse to zero.")
            }
        }
        let axes = [frame.xAxis, frame.yAxis, frame.zAxis]
        let f = [factors.x, factors.y, factors.z]
        // L = B · diag(f) · Bᵀ, then the translation keeps the pivot fixed.
        var values = Transform3D.identity.matrix.values
        for row in 0..<3 {
            for column in 0..<3 {
                var sum = 0.0
                for k in 0..<3 {
                    sum += component(axes[k], row) * f[k] * component(axes[k], column)
                }
                values[row * 4 + column] = sum
            }
        }
        let o = [frame.origin.x, frame.origin.y, frame.origin.z]
        for row in 0..<3 {
            let moved = (0..<3).reduce(0.0) { $0 + values[row * 4 + $1] * o[$1] }
            values[row * 4 + 3] = o[row] - moved
        }
        let transform = Transform3D(matrix: try Matrix4x4(values: values))
        try transform.validateAffinePlacement()
        return transform
    }

    /// A uniform scale about the pivot.
    public static func uniformScale(in frame: SceneTransformFrame, factor: Double) throws -> Transform3D {
        try scale(in: frame, factors: Vector3D(x: factor, y: factor, z: factor))
    }

    /// Freestyle move: the start point moves onto the end point.
    public static func freestyleMove(from start: Point3D, to end: Point3D) throws -> Transform3D {
        try Transform3D.translation(end - start)
    }

    /// Freestyle rotate: about the line from `axisStart` to `axisEnd`, turning `reference` until it
    /// points the way `target` does around that line.
    public static func freestyleRotation(
        axisStart: Point3D,
        axisEnd: Point3D,
        reference: Point3D,
        target: Point3D
    ) throws -> Transform3D {
        let axis = try direction(from: axisStart, to: axisEnd)
        let a = try perpendicular(reference - axisStart, to: axis, describing: "The rotation reference")
        let b = try perpendicular(target - axisStart, to: axis, describing: "The rotation target")
        let angle = atan2(axis.dot(a.cross(b)), a.dot(b))
        return try Transform3D.rotation(axis: axis, angleRadians: angle, about: axisStart)
    }

    /// Freestyle scale: along the line from `axisStart` to `axisEnd` about `axisStart` by `ratio`.
    public static func freestyleScale(axisStart: Point3D, axisEnd: Point3D, ratio: Double) throws -> Transform3D {
        let axis = try direction(from: axisStart, to: axisEnd)
        let frame = try SceneTransformFrame(origin: axisStart, normal: axis)
        return try scale(in: frame, factors: Vector3D(x: 1, y: 1, z: ratio))
    }

    /// The freestyle ratio that makes the axis span `length` long.
    public static func freestyleRatio(axisStart: Point3D, axisEnd: Point3D, length: Double) throws -> Double {
        let span = (axisEnd - axisStart).length
        guard span.isFinite, span > ModelingTolerance.standard.distance, length.isFinite, length > 0 else {
            throw EditorError(code: .commandInvalid, message: "A reference-length scale needs a nonzero axis and length.")
        }
        return length / span
    }

    /// The freestyle ratio that carries `axisEnd` to where `point` projects onto the axis.
    public static func freestyleRatio(axisStart: Point3D, axisEnd: Point3D, toward point: Point3D) throws -> Double {
        let axis = try direction(from: axisStart, to: axisEnd)
        let span = (axisEnd - axisStart).length
        return (point - axisStart).dot(axis) / span
    }

    private static func component(_ vector: Vector3D, _ index: Int) -> Double {
        index == 0 ? vector.x : (index == 1 ? vector.y : vector.z)
    }

    private static func direction(from start: Point3D, to end: Point3D) throws -> Vector3D {
        let vector = end - start
        guard vector.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "A freestyle axis needs two distinct points.")
        }
        return try vector.normalized(tolerance: ModelingTolerance.standard.distance)
    }

    private static func perpendicular(_ vector: Vector3D, to axis: Vector3D, describing name: String) throws -> Vector3D {
        let projected = vector - axis * vector.dot(axis)
        guard projected.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "\(name) lies on the rotation axis.")
        }
        return try projected.normalized(tolerance: ModelingTolerance.standard.distance)
    }
}
