struct ViewportActiveInteractionDragCandidates {
    var affordance: ViewportAffordanceDragState? = nil

    var firstActiveDrag: ViewportActiveInteractionDragState? {
        ViewportActiveInteractionDragKind.finishPrecedence.compactMap(state(for:)).first
    }

    func state(for kind: ViewportActiveInteractionDragKind) -> ViewportActiveInteractionDragState? {
        switch kind {
        case .affordance:
            affordance.map(ViewportActiveInteractionDragState.affordance)
        }
    }
}
