import RupaCore

public enum ViewportPatternArrayCopyCountSlot: String, Equatable, Sendable {
    case rectangularFirst
    case rectangularSecond
    case radialAngular
    case radialAxis
}

public struct ViewportPatternArrayCopyCountDragTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var slot: ViewportPatternArrayCopyCountSlot
    public var copyCount: Int

    public init(
        sourceID: PatternArraySourceID,
        slot: ViewportPatternArrayCopyCountSlot,
        copyCount: Int
    ) {
        self.sourceID = sourceID
        self.slot = slot
        self.copyCount = copyCount
    }
}
