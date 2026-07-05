public enum DrawingProjectionStylePreset: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case technical
    case presentation

    public var id: String {
        rawValue
    }
}
