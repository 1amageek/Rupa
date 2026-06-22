public enum BridgeCurveEndpointContinuity: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case g0
    case g1
    case g2
    case g3
}

public struct BridgeCurveContinuity: Codable, Equatable, Hashable, Sendable {
    public var first: BridgeCurveEndpointContinuity
    public var second: BridgeCurveEndpointContinuity

    public init(
        first: BridgeCurveEndpointContinuity,
        second: BridgeCurveEndpointContinuity
    ) {
        self.first = first
        self.second = second
    }

    public static let g0 = BridgeCurveContinuity(first: .g0, second: .g0)
    public static let g1 = BridgeCurveContinuity(first: .g1, second: .g1)
    public static let g2 = BridgeCurveContinuity(first: .g2, second: .g2)
    public static let g3 = BridgeCurveContinuity(first: .g3, second: .g3)
}
