import RupaCore

public struct ViewportPatternArrayOutputModeTarget: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var outputMode: PatternArrayOutputMode

    public init(
        sourceID: PatternArraySourceID,
        outputMode: PatternArrayOutputMode
    ) {
        self.sourceID = sourceID
        self.outputMode = outputMode
    }
}
