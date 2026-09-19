import Foundation
import SwiftCAD
import RupaCoreTypes

/// Composition for the placement transforms carried by scene nodes.
///
/// `Transform3D.matrix` stores its sixteen values column-major: element (row, column) lives at
/// `values[column * 4 + row]`, which puts the translation at indices 12, 13 and 14. Every operation
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
                    value += left[index * 4 + row] * right[column * 4 + index]
                }
                values[column * 4 + row] = value
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

    /// The point mapped through this transform.
    public func applied(to point: Point3D) throws -> Point3D {
        let m = try Self.matrixValues(of: self)
        let w = m[3] * point.x + m[7] * point.y + m[11] * point.z + m[15]
        guard w.isFinite, abs(w) > Self.singularDeterminantThreshold else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene node transform must not map a point to infinity."
            )
        }
        let mapped = Point3D(
            x: (m[0] * point.x + m[4] * point.y + m[8] * point.z + m[12]) / w,
            y: (m[1] * point.x + m[5] * point.y + m[9] * point.z + m[13]) / w,
            z: (m[2] * point.x + m[6] * point.y + m[10] * point.z + m[14]) / w
        )
        try mapped.validate()
        return mapped
    }

    public static func translation(_ vector: Vector3D) throws -> Transform3D {
        try vector.validate()
        var values = Matrix4x4.identity.values
        values[12] = vector.x
        values[13] = vector.y
        values[14] = vector.z
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
        values[1] = y * x * complement + z * sine
        values[2] = z * x * complement - y * sine
        values[4] = x * y * complement - z * sine
        values[5] = cosine + y * y * complement
        values[6] = z * y * complement + x * sine
        values[8] = x * z * complement + y * sine
        values[9] = y * z * complement - x * sine
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
        guard values.count == 16 else {
            throw EditorError(
                code: .commandInvalid,
                message: "A scene node transform must carry sixteen matrix values."
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
