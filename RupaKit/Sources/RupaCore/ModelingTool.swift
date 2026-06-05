import Foundation

public enum ModelingTool: String, CaseIterable, Hashable, Identifiable, Sendable {
    case select
    case sketch
    case solid
    case surface
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
        case .solid:
            "Solid"
        case .surface:
            "Surface"
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
        case .solid:
            "cube"
        case .surface:
            "square.stack.3d.up"
        case .mesh:
            "point.3.connected.trianglepath.dotted"
        case .measure:
            "ruler"
        case .section:
            "rectangle.split.2x1"
        }
    }
}
