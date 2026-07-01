import ArgumentParser
import RupaCore

enum CLI3DInputParser {
    static func point(
        x: Double,
        y: Double,
        z: Double,
        unit: LengthDisplayUnit,
        valueName: String
    ) throws -> Point3D {
        return Point3D(
            x: try coordinate(x, unit: unit, valueName: "\(valueName) x"),
            y: try coordinate(y, unit: unit, valueName: "\(valueName) y"),
            z: try coordinate(z, unit: unit, valueName: "\(valueName) z")
        )
    }

    static func vector(
        x: Double,
        y: Double,
        z: Double,
        valueName: String
    ) throws -> Vector3D {
        guard x.isFinite else {
            throw ValidationError("\(valueName) x must be finite.")
        }
        guard y.isFinite else {
            throw ValidationError("\(valueName) y must be finite.")
        }
        guard z.isFinite else {
            throw ValidationError("\(valueName) z must be finite.")
        }
        return Vector3D(x: x, y: y, z: z)
    }

    private static func coordinate(
        _ value: Double,
        unit: LengthDisplayUnit,
        valueName: String
    ) throws -> Double {
        guard value.isFinite else {
            throw ValidationError("\(valueName) must be finite.")
        }
        return unit.meters(from: value)
    }
}
