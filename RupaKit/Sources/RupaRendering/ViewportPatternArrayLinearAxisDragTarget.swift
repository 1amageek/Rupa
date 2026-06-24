import RupaCore

public enum ViewportPatternArrayLinearAxisSlot: String, Equatable, Sendable {
    case first
    case second
}

public struct ViewportPatternArrayLinearAxisDragTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var axisSlot: ViewportPatternArrayLinearAxisSlot
    public var distance: Double

    public init(
        sourceID: PatternArraySourceID,
        axisSlot: ViewportPatternArrayLinearAxisSlot,
        distance: Double
    ) {
        self.sourceID = sourceID
        self.axisSlot = axisSlot
        self.distance = distance
    }
}
