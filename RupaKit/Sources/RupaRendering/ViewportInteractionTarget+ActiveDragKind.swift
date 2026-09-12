extension ViewportInteractionTarget {
    /// The drag kind every interaction target finishes as.
    ///
    /// The mapping is total: the last target that resolved to no drag was the
    /// pattern array output mode toggle, and the native pattern input owns that
    /// click now. A target that cannot be dragged has no reason to exist here.
    var activeDragKind: ViewportActiveInteractionDragKind {
        switch self {
        case .splineControlPointSlide:
            .splineControlPointSlide
        case .polySplineSurfaceVertexSlide:
            .polySplineSurfaceVertexSlide
        case .surfaceControlPointSlide:
            .surfaceControlPointSlide
        case .surfaceFrame:
            .surfaceFrame
        case .regionOffset:
            .regionOffset
        case .edgeOffset:
            .edgeOffset
        case .slotWidth:
            .slotWidth
        case .sketchVertexOffset:
            .sketchVertexOffset
        case .patternArrayLinearAxis:
            .patternArrayLinearAxis
        case .independentCopyExtrudeDistance:
            .independentCopyExtrudeDistance
        case .independentCopyBodyDimension:
            .independentCopyBodyDimension
        case .affordance:
            .affordance
        }
    }
}
