enum ViewportActiveInteractionDragKind: CaseIterable, Equatable, Hashable {
    case sketchCurveHandle
    case sketchDimension
    case sketchPointHandle
    case splineControlPointSlide
    case polySplineSurfaceVertexSlide
    case surfaceControlPointSlide
    case surfaceFrame
    case splineControlPoint
    case polySplineSurfaceVertex
    case surfaceControlPoint
    case surfaceTrimEndpoint
    case surfaceTrimControlPoint
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
