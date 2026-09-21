public enum CADAngleUnit: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case degree
    case radian

    public var radiansPerUnit: Double {
        switch self {
        case .degree:
            .pi / 180.0
        case .radian:
            1.0
        }
    }
}
