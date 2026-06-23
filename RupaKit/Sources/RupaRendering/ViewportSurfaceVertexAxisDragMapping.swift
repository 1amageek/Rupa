import CoreGraphics
import RupaCore

struct ViewportSurfaceVertexAxisDragMapping {
    static func modelAmount(
        axisVector: CGVector,
        start: CGPoint,
        current: CGPoint
    ) -> Double {
        let axisLength = axisVector.length
        guard axisLength > 1.0e-9 else {
            return 0.0
        }
        let direction = axisVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        return Double(delta.dx * direction.dx + delta.dy * direction.dy) / Double(axisLength)
    }

    static func delta(
        axis: ViewportCoordinateAxis,
        amount: Double
    ) -> Point3D {
        switch axis {
        case .x:
            Point3D(x: amount, y: 0.0, z: 0.0)
        case .y:
            Point3D(x: 0.0, y: amount, z: 0.0)
        case .z:
            Point3D(x: 0.0, y: 0.0, z: amount)
        }
    }

    static func delta(
        direction: Vector3D,
        amount: Double
    ) -> Point3D {
        Point3D(
            x: direction.x * amount,
            y: direction.y * amount,
            z: direction.z * amount
        )
    }
}
