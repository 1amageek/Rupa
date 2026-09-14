enum ViewportActiveInteractionDragState: Equatable {
    case affordance(ViewportAffordanceDragState)

    var kind: ViewportActiveInteractionDragKind {
        switch self {
        case .affordance:
            .affordance
        }
    }

    var interactionTarget: ViewportInteractionTarget {
        switch self {
        case .affordance(let state):
            .affordance(state.target)
        }
    }

    var affordance: ViewportAffordanceDragState? {
        if case .affordance(let state) = self { state } else { nil }
    }
}
