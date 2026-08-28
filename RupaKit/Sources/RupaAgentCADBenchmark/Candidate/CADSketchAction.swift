public enum CADSketchAction: Codable, Equatable, Hashable, Sendable {
    case line(name: String, plane: CADSketchPlane, start: CADPoint3D, end: CADPoint3D)
    case rectangle(
        name: String,
        plane: CADSketchPlane,
        center: CADPoint3D,
        width: CADLength,
        height: CADLength
    )
}
