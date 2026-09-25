import Foundation
import SwiftCAD
import RupaCoreTypes

/// Composition for the placement transforms carried by scene nodes.
///
/// `Transform3D.matrix` stores its sixteen values row-major: element (row, column) lives at
/// `values[row * 4 + column]`, which puts the translation at indices 3, 7 and 11. Every operation
/// here reads and writes that layout, and every one of them fails loudly rather than returning an
/// approximation, because the results decide where geometry is placed in the document.
extension Transform3D {
    /// The transform that applies `self` after `other`.
    ///
    /// Composing a parent's world transform with a child's local transform in that order gives the
    /// child's world transform, which is the direction the scene graph is read in.
    public func composed(with other: Transform3D) throws -> Transform3D {
        let left = try Self.matrixValues(of: self)
        let right = try Self.matrixValues(of: other)
        var values = [Double](repeating: 0.0, count: 16)
        for column in 0 ..< 4 {
            for row in 0 ..< 4 {
                var value = 0.0
                for index in 0 ..< 4 {
                    value += left[row * 4 + index] * right[index * 4 + column]
                }
                values[row * 4 + column] = value
            }
        }
        return try Self.transform(values: values)
    }

    /// The transform that undoes `self`.
    ///
    /// Moving a node that hangs below other transforms means expressing a world-space motion in the
    /// node's parent space, and that requires the parent's inverse.
    public func inverse() throws -> Transform3D {
        let m = try Self.matrixValues(of: self)
        var inverted = [Double](repeating: 0.0, count: 16)

        inverted[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15]
            + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
        inverted[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15]
            - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
        inverted[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15]
            + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
        inverted[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14]
            - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
        inverted[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15]
            - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
        inverted[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15]
            + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
        inverted[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15]
            - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
        inverted[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14]
            + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
        inverted[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15]
            + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
        inverted[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15]
            - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
        inverted[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15]
            + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
        inverted[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14]
            - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
        inverted[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11]
            - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
        inverted[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11]
            + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
        inverted[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11]
            - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
        inverted[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10]
            + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]

        let determinant = m[0] * inverted[0] + m[1] * inverted[4] + m[2] * inverted[8] + m[3] * inverted[12]
        guard determinant.isFinite, abs(determinant) > Self.singularDeterminantThreshold else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene node transform must be invertible to place geometry relative to it."
            )
        }
        for index in inverted.indices {
            inverted[index] /= determinant
        }
        return try Self.transform(values: inverted)
    }

    /// Validates that this matrix can represent a Product placement.
    public func validateAffinePlacement() throws {
        let values = try Self.matrixValues(of: self)
        guard values[12] == 0.0,
              values[13] == 0.0,
              values[14] == 0.0,
              values[15] == 1.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene node placement must be affine."
            )
        }
        _ = try inverse()
    }

    /// Maps source-local coordinates into another placed frame; nil denotes equal frames.
    public func coordinateMap(to output: Transform3D) throws -> AffineTransform3D? {
        try validateAffinePlacement()
        try output.validateAffinePlacement()
        if self == output { return nil }
        let transform = try output.inverse().composed(with: self)
        let m = transform.matrix.values
        return try AffineTransform3D(
            basisX: Vector3D(x: m[0], y: m[4], z: m[8]),
            basisY: Vector3D(x: m[1], y: m[5], z: m[9]),
            basisZ: Vector3D(x: m[2], y: m[6], z: m[10]),
            translation: Vector3D(x: m[3], y: m[7], z: m[11])
        )
    }

    /// The point mapped through this transform.
    public func applied(to point: Point3D) throws -> Point3D {
        let m = try Self.matrixValues(of: self)
        let w = m[12] * point.x + m[13] * point.y + m[14] * point.z + m[15]
        guard w.isFinite, abs(w) > Self.singularDeterminantThreshold else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene node transform must not map a point to infinity."
            )
        }
        let mapped = Point3D(
            x: (m[0] * point.x + m[1] * point.y + m[2] * point.z + m[3]) / w,
            y: (m[4] * point.x + m[5] * point.y + m[6] * point.z + m[7]) / w,
            z: (m[8] * point.x + m[9] * point.y + m[10] * point.z + m[11]) / w
        )
        try mapped.validate()
        return mapped
    }

    /// Maps a direction through the linear part of an affine placement.
    public func applyingLinearPart(to vector: Vector3D) throws -> Vector3D {
        try validateAffinePlacement()
        try vector.validate()
        let values = try Self.matrixValues(of: self)
        let mapped = Vector3D(
            x: values[0] * vector.x + values[1] * vector.y + values[2] * vector.z,
            y: values[4] * vector.x + values[5] * vector.y + values[6] * vector.z,
            z: values[8] * vector.x + values[9] * vector.y + values[10] * vector.z
        )
        try mapped.validate()
        return mapped
    }

    /// Maps a direction from world space back into this placement's local frame.
    public func inverseApplyingLinearPart(to vector: Vector3D) throws -> Vector3D {
        try inverse().applyingLinearPart(to: vector)
    }

    /// Maps a plane normal through this affine placement, including non-uniform scale.
    public func applyingNormal(to normal: Vector3D) throws -> Vector3D {
        let inverse = try inverse()
        let values = try Self.matrixValues(of: inverse)
        try normal.validate()
        let mapped = Vector3D(
            x: values[0] * normal.x + values[4] * normal.y + values[8] * normal.z,
            y: values[1] * normal.x + values[5] * normal.y + values[9] * normal.z,
            z: values[2] * normal.x + values[6] * normal.y + values[10] * normal.z
        )
        try mapped.validate()
        let length = mapped.length
        guard length.isFinite, length > Self.singularDeterminantThreshold else {
            throw EditorError(code: .commandInvalid, message: "A transformed plane normal is degenerate.")
        }
        return mapped / length
    }

    public static func translation(_ vector: Vector3D) throws -> Transform3D {
        try vector.validate()
        var values = Matrix4x4.identity.values
        values[3] = vector.x
        values[7] = vector.y
        values[11] = vector.z
        return try transform(values: values)
    }

    /// A non-singular axis scale about `pivot`.
    public static func scale(_ factors: Vector3D, about pivot: Point3D) throws -> Transform3D {
        try factors.validate()
        try pivot.validate()
        guard abs(factors.x) > singularDeterminantThreshold,
              abs(factors.y) > singularDeterminantThreshold,
              abs(factors.z) > singularDeterminantThreshold else {
            throw EditorError(code: .commandInvalid, message: "A scene scale must be invertible.")
        }
        let values = [
            factors.x, 0.0, 0.0, pivot.x * (1.0 - factors.x),
            0.0, factors.y, 0.0, pivot.y * (1.0 - factors.y),
            0.0, 0.0, factors.z, pivot.z * (1.0 - factors.z),
            0.0, 0.0, 0.0, 1.0,
        ]
        return try transform(values: values)
    }

    /// A rotation of `angleRadians` around `axis`, taken through the world origin.
    public static func rotation(
        axis: Vector3D,
        angleRadians: Double
    ) throws -> Transform3D {
        try axis.validate()
        guard angleRadians.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "A rotation angle must be finite."
            )
        }
        let length = axis.length
        guard length.isFinite, length > singularDeterminantThreshold else {
            throw EditorError(
                code: .commandInvalid,
                message: "A rotation axis must have a non-zero length."
            )
        }
        let x = axis.x / length
        let y = axis.y / length
        let z = axis.z / length
        let cosine = cos(angleRadians)
        let sine = sin(angleRadians)
        let complement = 1.0 - cosine

        var values = Matrix4x4.identity.values
        values[0] = cosine + x * x * complement
        values[4] = y * x * complement + z * sine
        values[8] = z * x * complement - y * sine
        values[1] = x * y * complement - z * sine
        values[5] = cosine + y * y * complement
        values[9] = z * y * complement + x * sine
        values[2] = x * z * complement + y * sine
        values[6] = y * z * complement - x * sine
        values[10] = cosine + z * z * complement
        return try transform(values: values)
    }

    /// A rotation of `angleRadians` around the `axis` through `pivot`.
    ///
    /// Rotating a multi-object selection turns every member around one shared point, so the pivot is
    /// what makes the members hold their arrangement instead of each spinning in place.
    public static func rotation(
        axis: Vector3D,
        angleRadians: Double,
        about pivot: Point3D
    ) throws -> Transform3D {
        try pivot.validate()
        let rotation = try rotation(axis: axis, angleRadians: angleRadians)
        return try rotation.conjugated(about: pivot)
    }

    /// This transform re-expressed so that it acts around `pivot` instead of the world origin.
    public func conjugated(about pivot: Point3D) throws -> Transform3D {
        try pivot.validate()
        let toPivot = try Transform3D.translation(
            Vector3D(x: pivot.x, y: pivot.y, z: pivot.z)
        )
        let fromPivot = try Transform3D.translation(
            Vector3D(x: -pivot.x, y: -pivot.y, z: -pivot.z)
        )
        return try toPivot.composed(with: self).composed(with: fromPivot)
    }

    private static let singularDeterminantThreshold = 1.0e-12

    private static func matrixValues(of transform: Transform3D) throws -> [Double] {
        let values = transform.matrix.values
        guard values.count == 16, values.allSatisfy(\.isFinite) else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene node transform must carry sixteen finite matrix values."
            )
        }
        return values
    }

    private static func transform(values: [Double]) throws -> Transform3D {
        do {
            return Transform3D(matrix: try Matrix4x4(values: values))
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "A composed scene node transform must stay finite: \(error)."
            )
        }
    }
}
