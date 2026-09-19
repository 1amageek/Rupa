/// Projection modes exposed by the viewport control protocol.
public enum AgentViewportProjection: String, Codable, CaseIterable, Sendable {
    case parallel
    case perspective
}
