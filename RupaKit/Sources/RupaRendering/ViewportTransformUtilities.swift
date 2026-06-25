import RupaCore

extension Transform3D {
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
