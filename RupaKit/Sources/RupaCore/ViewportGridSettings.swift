import Foundation

public enum ViewportGridVisualSpacingMode: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case adaptive
    case fixed

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .adaptive:
            "Adaptive"
        case .fixed:
            "Fixed"
        }
    }
}

public struct ViewportGridSettings: Codable, Hashable, Sendable {
    public var visualSpacingMode: ViewportGridVisualSpacingMode

    public init(
        visualSpacingMode: ViewportGridVisualSpacingMode = .adaptive
    ) {
        self.visualSpacingMode = visualSpacingMode
    }

    public static let standard = ViewportGridSettings()

    public var summary: String {
        "Viewport grid visual spacing \(visualSpacingMode.title.lowercased())."
    }
}
