import RupaCore

public struct ViewportPatternArrayCurvePathPointDragTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var pointIndex: Int
    public var point: Point3D

    public init(
        sourceID: PatternArraySourceID,
        pointIndex: Int,
        point: Point3D
    ) {
        self.sourceID = sourceID
        self.pointIndex = pointIndex
        self.point = point
    }
}
