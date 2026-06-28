public enum DesignProcessRouteStatus: String, Codable, Equatable, Sendable {
    case planned
    case partial
    case connected
    case verified
    case missing
    case unsupported
}
