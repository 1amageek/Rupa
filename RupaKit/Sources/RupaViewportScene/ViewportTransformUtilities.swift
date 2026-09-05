import RupaCore

extension Transform3D {
    package func concatenating(_ rhs: Transform3D) -> Transform3D {
        let left = matrix.values
        let right = rhs.matrix.values
        guard left.count == 16,
              right.count == 16 else {
            return self
        }
        var values = Array(repeating: 0.0, count: 16)
        for column in 0 ..< 4 {
            for row in 0 ..< 4 {
                var value = 0.0
                for index in 0 ..< 4 {
                    value += left[row * 4 + index] * right[index * 4 + column]
                }
                values[row * 4 + column] = value
            }
        }
        do {
            return Transform3D(matrix: try Matrix4x4(values: values))
        } catch {
            return self
        }
    }

    package func viewportTransformedPoint(_ point: Point3D) -> Point3D {
        let values = matrix.values
        guard values.count == 16 else {
            return point
        }
        let w = values[12] * point.x
            + values[13] * point.y
            + values[14] * point.z
            + values[15]
        let scale = abs(w) > 1.0e-12 ? 1.0 / w : 1.0
        return Point3D(
            x: (values[0] * point.x + values[1] * point.y + values[2] * point.z + values[3]) * scale,
            y: (values[4] * point.x + values[5] * point.y + values[6] * point.z + values[7]) * scale,
            z: (values[8] * point.x + values[9] * point.y + values[10] * point.z + values[11]) * scale
        )
    }

    package func viewportTransformedVector(_ vector: Vector3D) -> Vector3D {
        let values = matrix.values
        guard values.count == 16 else {
            return vector
        }
        return Vector3D(
            x: values[0] * vector.x + values[1] * vector.y + values[2] * vector.z,
            y: values[4] * vector.x + values[5] * vector.y + values[6] * vector.z,
            z: values[8] * vector.x + values[9] * vector.y + values[10] * vector.z
        )
    }

    package func viewportInverseTransformedVector(_ vector: Vector3D) -> Vector3D? {
        let values = matrix.values
        guard values.count == 16 else {
            return vector
        }
        let a = values[0]
        let b = values[1]
        let c = values[2]
        let d = values[4]
        let e = values[5]
        let f = values[6]
        let g = values[8]
        let h = values[9]
        let i = values[10]
        let determinant = a * (e * i - f * h)
            - b * (d * i - f * g)
            + c * (d * h - e * g)
        guard abs(determinant) > 1.0e-12 else {
            return nil
        }
        return Vector3D(
            x: ((e * i - f * h) * vector.x
                + (c * h - b * i) * vector.y
                + (b * f - c * e) * vector.z) / determinant,
            y: ((f * g - d * i) * vector.x
                + (a * i - c * g) * vector.y
                + (c * d - a * f) * vector.z) / determinant,
            z: ((d * h - e * g) * vector.x
                + (b * g - a * h) * vector.y
                + (a * e - b * d) * vector.z) / determinant
        )
    }
}
