/// Named camera orientations and the custom state produced by incremental camera operations.
public enum AgentViewportOrientation: String, Codable, CaseIterable, Sendable {
    case isometric
    case xFront
    case yFront
    case zFront
    case custom
}
