import SwiftCAD

public struct CurveEvaluationSample: Codable, Equatable, Sendable {
    public var parameter: Double
    public var point: CADCore.Point2D
    public var tangent: CADCore.Point2D
    public var normal: CADCore.Point2D
    public var curvature: Double

    public init(
        parameter: Double,
        point: CADCore.Point2D,
        tangent: CADCore.Point2D,
        normal: CADCore.Point2D,
        curvature: Double
    ) {
        self.parameter = parameter
        self.point = point
        self.tangent = tangent
        self.normal = normal
        self.curvature = curvature
    }
}
