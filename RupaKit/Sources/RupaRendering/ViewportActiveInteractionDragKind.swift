enum ViewportActiveInteractionDragKind: CaseIterable, Equatable, Hashable {
    case affordance

    static var finishPrecedence: [ViewportActiveInteractionDragKind] {
        allCases
    }
}
