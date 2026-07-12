import Foundation

public struct GeometryTransform3D: Codable, Equatable, Sendable {
    public let values: [Double]

    public init(values: [Double]) throws {
        guard values.count == 16, values.allSatisfy(\.isFinite) else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry transforms require sixteen finite matrix values."
            )
        }
        self.values = values
    }

    private init(validatedValues: [Double]) {
        self.values = validatedValues
    }

    public static let identity = GeometryTransform3D(validatedValues: [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])

    public func multiplied(by other: GeometryTransform3D) throws -> GeometryTransform3D {
        var result = Array(repeating: 0.0, count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                result[row * 4 + column] = (0..<4).reduce(0) { partial, index in
                    partial + values[row * 4 + index] * other.values[index * 4 + column]
                }
            }
        }
        return try GeometryTransform3D(values: result)
    }

    public func applying(to point: GeometryPoint3D) throws -> GeometryPoint3D {
        let x = values[0] * point.x + values[1] * point.y + values[2] * point.z + values[3]
        let y = values[4] * point.x + values[5] * point.y + values[6] * point.z + values[7]
        let z = values[8] * point.x + values[9] * point.y + values[10] * point.z + values[11]
        let w = values[12] * point.x + values[13] * point.y + values[14] * point.z + values[15]
        guard w != 0 else {
            throw MeshSourceError(
                code: .invalidBuffer,
                message: "Geometry transform produced a point at infinity."
            )
        }
        let transformed = w == 1
            ? GeometryPoint3D(x: x, y: y, z: z)
            : GeometryPoint3D(x: x / w, y: y / w, z: z / w)
        try transformed.validate()
        return transformed
    }
}
