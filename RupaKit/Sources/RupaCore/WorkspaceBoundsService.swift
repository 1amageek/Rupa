import SwiftCAD

public struct WorkspaceBoundsService: Sendable {
    public init() {}

    public func bounds(
        for evaluatedDocument: EvaluatedDocument
    ) -> MeasurementResult.Bounds? {
        var accumulator = MeasurementBoundsAccumulator()
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

}
