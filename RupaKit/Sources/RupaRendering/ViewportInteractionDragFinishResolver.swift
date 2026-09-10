enum ViewportInteractionDragFinishRequest: Equatable {
    case none
    case finish(ViewportActiveInteractionDragKind)
}

enum ViewportInteractionDragFinishResolver {
    static func request(
        pendingTarget: ViewportInteractionTarget?,
        activeInteractionDrags: ViewportActiveInteractionDrags
    ) -> ViewportInteractionDragFinishRequest {
        if let pendingTarget {
            return .finish(pendingTarget.activeDragKind)
        }

        guard let finishKind = activeInteractionDrags.nextFinishKind else {
            return .none
        }
        return .finish(finishKind)
    }
}
