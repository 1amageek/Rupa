import RupaCore

enum ViewportSnapOverlayContext: Equatable {
    case passiveHover
    case creationDrag

    init(activeCanvasDrag: ViewportActiveDrag?) {
        guard let activeCanvasDrag,
              case .creation = activeCanvasDrag.kind else {
            self = .passiveHover
            return
        }
        self = .creationDrag
    }
}

enum ViewportSnapOverlayPolicy {
    static func drawsOverlay(
        kind: SnapCandidateKind,
        context: ViewportSnapOverlayContext
    ) -> Bool {
        switch (kind, context) {
        case (.grid, .passiveHover):
            return false
        case (.grid, .creationDrag):
            return true
        default:
            return true
        }
    }

    static func drawsLabel(
        kind: SnapCandidateKind,
        context: ViewportSnapOverlayContext
    ) -> Bool {
        switch (kind, context) {
        case (.grid, _):
            return false
        default:
            return true
        }
    }

    static func publishedKind(
        _ kind: SnapCandidateKind?,
        context: ViewportSnapOverlayContext
    ) -> SnapCandidateKind? {
        guard let kind,
              drawsOverlay(kind: kind, context: context) else {
            return nil
        }
        return kind
    }
}
