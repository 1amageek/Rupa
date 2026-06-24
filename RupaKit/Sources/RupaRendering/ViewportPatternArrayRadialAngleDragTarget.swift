import RupaCore

public struct ViewportPatternArrayRadialAngleDragTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var angleRadians: Double

    public init(
        sourceID: PatternArraySourceID,
        angleRadians: Double
    ) {
        self.sourceID = sourceID
        self.angleRadians = angleRadians
    }
}
