import Foundation

public enum ModelingTool: String, CaseIterable, Hashable, Identifiable, Sendable {
    case select
    case sketch
    case polygon
    case circle
    case arc
    case spline
    case solid
    case sweep
    case mesh
    case measure
    case section

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .select:
            "Select"
        case .sketch:
            "Sketch"
        case .polygon:
            "Polygon"
        case .circle:
            "Circle"
        case .arc:
            "Arc"
        case .spline:
            "Spline"
        case .solid:
            "Solid"
        case .sweep:
            "Sweep"
        case .mesh:
            "Mesh"
        case .measure:
            "Measure"
        case .section:
            "Section"
        }
    }

    public var systemImage: String {
        switch self {
        case .select:
            "cursorarrow"
        case .sketch:
            "pencil.and.outline"
        case .polygon:
            "hexagon"
        case .circle:
            "circle"
        case .arc:
            "point.topleft.down.curvedto.point.bottomright.up"
        case .spline:
            "waveform.path.ecg"
        case .solid:
            "cube"
        case .sweep:
            "arrow.triangle.2.circlepath"
        case .mesh:
            "point.3.connected.trianglepath.dotted"
        case .measure:
            "ruler"
        case .section:
            "rectangle.split.2x1"
        }
    }
}
