public enum SketchDimensionInputFocus: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case length
    case angle
    case width
    case height

    public var statusTitle: String {
        switch self {
        case .length:
            return "Length"
        case .angle:
            return "Angle"
        case .width:
            return "Width"
        case .height:
            return "Height"
        }
    }
}
