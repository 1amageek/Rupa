public enum CADInteractionQualityRating: String, Codable, Equatable, Sendable {
    case missing
    case planned
    case partial
    case implemented
    case verified

    public var score: Int {
        switch self {
        case .missing:
            0
        case .planned:
            1
        case .partial:
            2
        case .implemented:
            3
        case .verified:
            4
        }
    }
}
