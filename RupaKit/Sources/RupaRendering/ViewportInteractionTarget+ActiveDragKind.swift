extension ViewportInteractionTarget {
    /// The drag kind every interaction target finishes as.
    ///
    /// The mapping is total because the prepared native record produces a
    /// single claim, and that claim is draggable. A target that cannot be
    /// dragged has no reason to exist here.
    var activeDragKind: ViewportActiveInteractionDragKind {
        switch self {
        case .affordance:
            .affordance
        }
    }
}
