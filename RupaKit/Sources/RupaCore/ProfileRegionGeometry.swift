import Foundation
import SwiftCAD

struct ProfileRegionGeometry: Sendable {
    struct Summary: Equatable, Sendable {
        var center: Point2D
        var areaSquareMeters: Double
        var points: [Point2D]
    }

    static func summary(for profile: Profile) -> Summary? {
        let points = profile.vertices.compactMap { vertex in
            projectedPoint(vertex, on: profile.plane)
        }
        guard points.count >= 3 else {
            return nil
        }

        var twiceArea = 0.0
        var weightedX = 0.0
        var weightedY = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let cross = current.x * next.y - next.x * current.y
            twiceArea += cross
            weightedX += (current.x + next.x) * cross
            weightedY += (current.y + next.y) * cross
        }
        guard abs(twiceArea) > 1.0e-18 else {
            return nil
        }

        let center = Point2D(
            x: weightedX / (3.0 * twiceArea),
            y: weightedY / (3.0 * twiceArea)
        )
        guard center.x.isFinite && center.y.isFinite else {
            return nil
        }

        return Summary(
            center: center,
            areaSquareMeters: abs(twiceArea) * 0.5,
            points: points
        )
    }

    private static func projectedPoint(
        _ point: Point3D,
        on plane: SketchPlane
    ) -> Point2D? {
        switch plane {
        case .xy:
            return Point2D(x: point.x, y: point.y)
        case .yz:
            return Point2D(x: point.y, y: point.z)
        case .zx:
            return Point2D(x: point.z, y: point.x)
        case .plane(let plane):
            do {
                let normal = try plane.normal.normalized(tolerance: 1.0e-9)
                let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
                let u = try helper.cross(normal).normalized(tolerance: 1.0e-9)
                let v = normal.cross(u)
                let delta = Vector3D(
                    x: point.x - plane.origin.x,
                    y: point.y - plane.origin.y,
                    z: point.z - plane.origin.z
                )
                return Point2D(x: delta.dot(u), y: delta.dot(v))
            } catch {
                return nil
            }
        }
    }
}
