public enum BridgeCurveTrimSide: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case towardStart
    case towardEnd

    public var keepsLowerParameterSide: Bool {
        self == .towardStart
    }

    public var reversed: BridgeCurveTrimSide {
        switch self {
        case .towardStart:
            return .towardEnd
        case .towardEnd:
            return .towardStart
        }
    }
}
