enum ViewportActiveInteractionDragKind: CaseIterable, Equatable, Hashable {
    case splineControlPointSlide
    case polySplineSurfaceVertexSlide
    case surfaceControlPointSlide
    case surfaceFrame
    case edgeOffset
    case slotWidth
    case independentCopyExtrudeDistance
    case independentCopyBodyDimension
    case patternArrayLinearAxis
    case sketchVertexOffset
    case regionOffset
    case affordance

    static var finishPrecedence: [ViewportActiveInteractionDragKind] {
        allCases
    }
}
