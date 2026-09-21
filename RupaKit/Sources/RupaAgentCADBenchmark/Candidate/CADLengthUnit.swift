public enum CADLengthUnit: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case millimeter
    case centimeter
    case meter
    case inch

    public var metersPerUnit: Double {
        switch self {
        case .millimeter:
            0.001
        case .centimeter:
            0.01
        case .meter:
            1.0
        case .inch:
            0.0254
        }
    }

    public var symbol: String {
        switch self {
        case .millimeter:
            "mm"
        case .centimeter:
            "cm"
        case .meter:
            "m"
        case .inch:
            "in"
        }
    }
}
