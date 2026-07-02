import SwiftCAD

public struct WorkspaceBoundsService: Sendable {
    public init() {}

    public func bounds(
        for evaluatedDocument: EvaluatedDocument
    ) -> MeasurementResult.Bounds? {
        var accumulator = Accumulator()
        for mesh in evaluatedDocument.meshes.values {
            accumulator.include(mesh.positions)
        }
        for curves in evaluatedDocument.curves.values {
            for curve in curves {
                accumulator.include(curve.points)
            }
        }
        return accumulator.bounds
    }

    private struct Accumulator {
        private(set) var bounds: MeasurementResult.Bounds?

        mutating func include<S: Sequence>(_ points: S) where S.Element == Point3D {
            for point in points {
                include(point)
            }
        }

        mutating func include(_ point: Point3D) {
            let next = MeasurementResult.Bounds(
                minX: point.x,
                minY: point.y,
                minZ: point.z,
                maxX: point.x,
                maxY: point.y,
                maxZ: point.z
            )
            guard let current = bounds else {
                bounds = next
                return
            }
            bounds = MeasurementResult.Bounds(
                minX: min(current.minX, next.minX),
                minY: min(current.minY, next.minY),
                minZ: min(current.minZ, next.minZ),
                maxX: max(current.maxX, next.maxX),
                maxY: max(current.maxY, next.maxY),
                maxZ: max(current.maxZ, next.maxZ)
            )
        }
    }
}
