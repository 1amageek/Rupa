import RupaCore

public struct ViewportPatternArrayCurvePathReplacementPreviewRequest: Equatable, Sendable {
    public var sourceID: PatternArraySourceID
    public var path: PatternArrayCurvePath
    public var title: String

    public init(
        sourceID: PatternArraySourceID,
        path: PatternArrayCurvePath,
        title: String
    ) {
        self.sourceID = sourceID
        self.path = path
        self.title = title
    }
}
