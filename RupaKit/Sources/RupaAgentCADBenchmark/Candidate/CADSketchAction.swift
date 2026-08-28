public enum CADSketchAction: Codable, Equatable, Hashable, Sendable {
    case line(name: String, plane: CADSketchPlane, start: CADPoint3D, end: CADPoint3D)
}
