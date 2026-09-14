struct ViewportActiveInteractionDrags: Equatable {
    private var activeDrag: ViewportActiveInteractionDragState?

    init(affordance: ViewportAffordanceDragState? = nil) {
        activeDrag = ViewportActiveInteractionDragCandidates(
            affordance: affordance
        ).firstActiveDrag
    }

    var affordance: ViewportAffordanceDragState? {
        get { activeDrag?.affordance }
        set {
            setActiveDrag(newValue.map(ViewportActiveInteractionDragState.affordance), replacing: .affordance)
        }
    }

    var hasActiveDrag: Bool {
        activeDrag != nil
    }

    var nextFinishKind: ViewportActiveInteractionDragKind? {
        activeDrag?.kind
    }

    mutating func clear(except preservedTarget: ViewportInteractionTarget? = nil) {
        if activeDrag?.interactionTarget != preservedTarget {
            activeDrag = nil
        }
    }

    private mutating func setActiveDrag(
        _ newActiveDrag: ViewportActiveInteractionDragState?,
        replacing kind: ViewportActiveInteractionDragKind
    ) {
        guard let newActiveDrag else {
            if activeDrag?.kind == kind {
                activeDrag = nil
            }
            return
        }
        activeDrag = newActiveDrag
    }
}
