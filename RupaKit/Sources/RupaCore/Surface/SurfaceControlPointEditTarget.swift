public enum SurfaceControlPointEditTarget: Equatable, Sendable {
    case boundaryVertex(SelectionTarget)
    case interiorControlPoint(PolySplineSurfaceControlPointEditTarget)
    case bSplineSurfaceControlPoint(BSplineSurfaceControlPointEditTarget)
}
