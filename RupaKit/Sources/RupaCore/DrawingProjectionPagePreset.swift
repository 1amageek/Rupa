public enum DrawingProjectionPagePreset: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case letterLandscape
    case letterPortrait
    case a4Landscape
    case a4Portrait

    public var id: String {
        rawValue
    }

    public var page: DrawingProjectionPage {
        switch self {
        case .letterLandscape:
            DrawingProjectionPage(width: 792.0, height: 612.0)
        case .letterPortrait:
            DrawingProjectionPage(width: 612.0, height: 792.0)
        case .a4Landscape:
            DrawingProjectionPage(width: 841.889764, height: 595.275590)
        case .a4Portrait:
            DrawingProjectionPage(width: 595.275590, height: 841.889764)
        }
    }
}
