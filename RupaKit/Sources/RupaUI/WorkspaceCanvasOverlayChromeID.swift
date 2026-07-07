import RupaRendering

enum WorkspaceCanvasOverlayChromeID: Hashable {
    case topBar
    case toolPalette
    case utilityRail
    case contextPanel

    var fittingEdges: ViewportCanvasFittingEdges {
        switch self {
        case .topBar:
            return .top
        case .toolPalette:
            return .leading
        case .utilityRail:
            return .trailing
        case .contextPanel:
            return .bottom
        }
    }
}
