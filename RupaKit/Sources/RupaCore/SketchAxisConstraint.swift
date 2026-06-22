import Foundation
import SwiftCAD

public enum SketchAxisConstraint: String, Codable, Equatable, Sendable {
    case x
    case y
    case z

    private struct PlaneFrame {
        var normal: Vector3D
        var u: Vector3D
        var v: Vector3D
    }

    public var statusTitle: String {
        rawValue.uppercased()
    }

    public func constrainedCanvasPoint(
        _ point: Point2D,
        from reference: Point2D,
        on plane: SketchPlane
    ) -> Point2D {
        let currentLocalPoint = localPoint(fromCanvas: point, on: plane)
        let referenceLocalPoint = localPoint(fromCanvas: reference, on: plane)
        guard let direction = localDirection(on: plane) else {
            return point
        }

        let deltaX = currentLocalPoint.x - referenceLocalPoint.x
        let deltaY = currentLocalPoint.y - referenceLocalPoint.y
        let projection = deltaX * direction.x + deltaY * direction.y
        let constrainedLocalPoint = Point2D(
            x: referenceLocalPoint.x + direction.x * projection,
            y: referenceLocalPoint.y + direction.y * projection
        )
        return canvasPoint(fromLocal: constrainedLocalPoint, on: plane)
    }

    private func localDirection(on plane: SketchPlane) -> Point2D? {
        guard let frame = planeFrame(for: plane) else {
            return nil
        }
        let axis = worldAxisVector()
        let projected = axis - frame.normal * axis.dot(frame.normal)
        let localX = projected.dot(frame.u)
        let localY = projected.dot(frame.v)
        let length = (localX * localX + localY * localY).squareRoot()
        guard length > 1.0e-12 else {
            return nil
        }
        return Point2D(x: localX / length, y: localY / length)
    }

    private func worldAxisVector() -> Vector3D {
        switch self {
        case .x:
            return .unitX
        case .y:
            return .unitY
        case .z:
            return .unitZ
        }
    }

    private func planeFrame(for plane: SketchPlane) -> PlaneFrame? {
        switch plane {
        case .xy:
            return PlaneFrame(normal: .unitZ, u: .unitX, v: .unitY)
        case .yz:
            return PlaneFrame(normal: .unitX, u: .unitY, v: .unitZ)
        case .zx:
            return PlaneFrame(normal: .unitY, u: .unitZ, v: .unitX)
        case .plane(let plane):
            do {
                let normal = try plane.normal.normalized(tolerance: 1.0e-12)
                let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
                let u = try helper.cross(normal).normalized(tolerance: 1.0e-12)
                let v = normal.cross(u)
                return PlaneFrame(normal: normal, u: u, v: v)
            } catch {
                return nil
            }
        }
    }

    private func localPoint(fromCanvas point: Point2D, on plane: SketchPlane) -> Point2D {
        switch plane {
        case .xy, .yz, .plane:
            return point
        case .zx:
            return Point2D(x: point.y, y: point.x)
        }
    }

    private func canvasPoint(fromLocal point: Point2D, on plane: SketchPlane) -> Point2D {
        switch plane {
        case .xy, .yz, .plane:
            return point
        case .zx:
            return Point2D(x: point.y, y: point.x)
        }
    }
}
