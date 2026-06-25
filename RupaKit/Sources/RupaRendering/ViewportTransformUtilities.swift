import RupaCore

extension Transform3D {
    func concatenating(_ rhs: Transform3D) -> Transform3D {
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
                    value += left[index * 4 + row] * right[column * 4 + index]
                }
                values[column * 4 + row] = value
            }
        }
        do {
            return Transform3D(matrix: try Matrix4x4(values: values))
        } catch {
            return self
        }
    }

    func viewportTransformedPoint(_ point: Point3D) -> Point3D {
        let values = matrix.values
        guard values.count == 16 else {
            return point
        }
        let w = values[3] * point.x
            + values[7] * point.y
            + values[11] * point.z
            + values[15]
        let scale = abs(w) > 1.0e-12 ? 1.0 / w : 1.0
        return Point3D(
            x: (values[0] * point.x + values[4] * point.y + values[8] * point.z + values[12]) * scale,
            y: (values[1] * point.x + values[5] * point.y + values[9] * point.z + values[13]) * scale,
            z: (values[2] * point.x + values[6] * point.y + values[10] * point.z + values[14]) * scale
        )
    }

    func viewportTransformedVector(_ vector: Vector3D) -> Vector3D {
        let values = matrix.values
        guard values.count == 16 else {
            return vector
        }
        return Vector3D(
            x: values[0] * vector.x + values[4] * vector.y + values[8] * vector.z,
            y: values[1] * vector.x + values[5] * vector.y + values[9] * vector.z,
            z: values[2] * vector.x + values[6] * vector.y + values[10] * vector.z
        )
    }
}
