enum ViewportActiveInteractionDragKind: CaseIterable, Equatable, Hashable {
    case sketchCurveHandle
    case sketchDimension
    case sketchPointHandle
    case splineControlPointSlide
    case polySplineSurfaceVertexSlide
    case surfaceControlPointSlide
    case surfaceFrame
    case splineControlPoint
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
