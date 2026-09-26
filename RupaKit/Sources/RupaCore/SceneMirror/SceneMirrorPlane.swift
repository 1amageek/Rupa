import SwiftCAD
import RupaCoreTypes

/// A world plane an object is mirrored across; the reflection lands on the side `normal` points to.
public struct SceneMirrorPlane: Codable, Hashable, Sendable {
    public var origin: Point3D
    public var normal: Vector3D

    public init(origin: Point3D, normal: Vector3D) throws {
        guard normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
              normal.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "A mirror plane needs a nonzero normal.")
        }
        self.origin = origin
        self.normal = try normal.normalized(tolerance: ModelingTolerance.standard.distance)
    }

    /// The plane through the construction plane origin perpendicular to one of its axes, on the
    /// positive or negative side of that axis.
    public static func axis(
        _ axis: SceneTransformAxis,
        positive: Bool,
        constructionPlane: SketchPlane
    ) throws -> SceneMirrorPlane {
        let system = try SketchPlaneCoordinateSystem(plane: constructionPlane)
        let direction: Vector3D = switch axis {
        case .x: system.u
        case .y: system.v
        case .z: system.normal
        }
        return try SceneMirrorPlane(origin: system.origin, normal: positive ? direction : direction * -1)
    }

    /// The plane containing the line from `start` to `end` and the construction plane normal.
    public static func freestyle(start: Point3D, end: Point3D, constructionPlane: SketchPlane) throws -> SceneMirrorPlane {
        let system = try SketchPlaneCoordinateSystem(plane: constructionPlane)
        let line = end - start
        guard line.length > ModelingTolerance.standard.distance else {
            throw EditorError(code: .commandInvalid, message: "A freestyle mirror needs two distinct points.")
        }
        let normal = system.normal.cross(line)
        guard normal.length > ModelingTolerance.standard.distance * line.length else {
            throw EditorError(
                code: .commandInvalid,
                message: "A freestyle mirror line must not run along the construction plane normal."
            )
        }
        return try SceneMirrorPlane(origin: start, normal: normal)
    }

    /// The world reflection across the plane.
    public func reflection() throws -> Transform3D {
        let n = [normal.x, normal.y, normal.z]
        let d = origin.x * normal.x + origin.y * normal.y + origin.z * normal.z
        var values = Transform3D.identity.matrix.values
        for row in 0..<3 {
            for column in 0..<3 {
                values[row * 4 + column] = (row == column ? 1 : 0) - 2 * n[row] * n[column]
            }
            values[row * 4 + 3] = 2 * d * n[row]
        }
        return Transform3D(matrix: try Matrix4x4(values: values))
    }
}
