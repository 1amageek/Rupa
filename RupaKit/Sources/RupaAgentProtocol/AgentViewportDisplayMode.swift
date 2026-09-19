/// Display modes that may be selected by a viewport operation.
public enum AgentViewportDisplayMode: String, Codable, CaseIterable, Sendable {
    case solid
    case solidWithEdges
    case wireframe
    case normals
}
