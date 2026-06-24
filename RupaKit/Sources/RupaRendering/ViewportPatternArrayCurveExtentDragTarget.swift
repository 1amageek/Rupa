import RupaCore

public enum ViewportPatternArrayCurveExtentDragValue: Equatable, Sendable {
    case distance(Double)
    case ratio(Double)
}

public struct ViewportPatternArrayCurveExtentDragTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var extent: ViewportPatternArrayCurveExtentDragValue

    public init(
        sourceID: PatternArraySourceID,
        extent: ViewportPatternArrayCurveExtentDragValue
    ) {
        self.sourceID = sourceID
        self.extent = extent
    }
}
