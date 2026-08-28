public enum CADSketchPlane: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case xy
    case xz
    case yz

    public var normal: CADDirection3D {
        switch self {
        case .xy:
            CADDirection3D(x: 0.0, y: 0.0, z: 1.0)
        case .xz:
            CADDirection3D(x: 0.0, y: 1.0, z: 0.0)
        case .yz:
            CADDirection3D(x: 1.0, y: 0.0, z: 0.0)
        }
    }

    public func frame(anchor: CADPoint3D) -> CADPlaneFrame {
        CADPlaneFrame(orientation: self, origin: anchor)
    }
}
