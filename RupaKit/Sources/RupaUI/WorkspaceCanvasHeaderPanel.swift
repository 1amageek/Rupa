/// The header panels that are presented as popovers.
///
/// One optional value of this type says which panel is open, so opening one
/// closes the other and neither can be open twice.
enum WorkspaceCanvasHeaderPanel: String, Hashable, Sendable {
    case analysis
    case more

    var title: String {
        switch self {
        case .analysis:
            "Surface Analysis"
        case .more:
            "More Canvas Controls"
        }
    }

    var systemImage: String {
        switch self {
        case .analysis:
            "circle.lefthalf.filled"
        case .more:
            "ellipsis"
        }
    }

    var accessibilityIdentifier: String {
        "WorkspaceCanvasHeader.\(rawValue)"
    }
}
