enum ViewportInteractionDragFinishRequest: Equatable {
    case none
    case clearCanvasDrag
    case finish(ViewportActiveInteractionDragKind)
}

enum ViewportInteractionDragFinishResolver {
    static func request(
        pendingTarget: ViewportInteractionTarget?,
        activeInteractionDrags: ViewportActiveInteractionDrags
    ) -> ViewportInteractionDragFinishRequest {
        if let pendingTarget {
            guard let finishKind = pendingTarget.activeDragKind else {
                return .clearCanvasDrag
            }
            return .finish(finishKind)
        }

        guard let finishKind = activeInteractionDrags.nextFinishKind else {
            return .none
        }
        return .finish(finishKind)
    }
}
