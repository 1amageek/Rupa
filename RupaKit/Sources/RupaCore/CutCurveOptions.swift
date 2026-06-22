public struct CutCurveOptions: Codable, Equatable, Sendable {
    public var extendsCutter: Bool
    public var usesScreenSpaceDirection: Bool

    public init(
        extendsCutter: Bool = false,
        usesScreenSpaceDirection: Bool = false
    ) {
        self.extendsCutter = extendsCutter
        self.usesScreenSpaceDirection = usesScreenSpaceDirection
    }
}
