import RupaRendering

/// The chrome the canvas carries on its own edges.
///
/// The header is not here: it is a real bar above the canvas, so it covers no
/// part of the viewport and reserves no exclusion in it. What remains lands on
/// opposite edges, which is why neither can take height from the other.
enum WorkspaceCanvasOverlayChromeID: Hashable, CaseIterable {
    case toolPalette
    case contextPanel

    var fittingEdges: ViewportCanvasFittingEdges {
        switch self {
        case .toolPalette: return .leading
        case .contextPanel: return .bottom
        }
    }
}
