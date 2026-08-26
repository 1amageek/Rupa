import RupaGeometry

public enum ViewportGeometryBoundsSource: Equatable, Sendable {
    case scene
    case geometry(GeometryBounds3D?)
}
