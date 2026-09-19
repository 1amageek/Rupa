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

    /// What the tool does, in the words the palette, the menu and the
    /// accessibility hint all show.
    public var summary: String {
        switch self {
        case .select:
            "Select Components"
        case .sketch:
            "Create Rectangle Sketch"
        case .polygon:
            "Create Regular Polygon"
        case .circle:
            "Create Circle Profile"
        case .arc:
            "Create Arc Curve"
        case .spline:
            "Create Spline Curve"
        case .solid:
            "Create Box"
        case .sweep:
            "Create Sweep from selected profile, selected guides, and clicked path"
        case .surface:
            "Open sheet Loft draft"
        case .mesh:
            "Edit Authored Mesh elements or make selected CAD editable"
        case .measure:
            "Measure two points in world space"
        case .section:
            "Create a section plane at the clicked point"
        }
    }

    /// The input the tool still needs once it is active.
    ///
    /// A tool is picked before it is used, and the gap between the two is
    /// where a user has to guess what to click. Activation reports this line
    /// so the answer arrives with the mode rather than after a click that did
    /// nothing.
    public var activationPrompt: String {
        switch self {
        case .select:
            "Click a component, or drag a gizmo handle to move the selection."
        case .sketch:
            "Click or drag on the effective plane to place a rectangle."
        case .polygon:
            "Click or drag on the effective plane. Up and Down change the side count."
        case .circle:
            "Click for a center, or drag from the center to the edge for a radius."
        case .arc:
            "Click or drag on the effective plane to place an arc."
        case .spline:
            "Click or drag on the effective plane to place a spline."
        case .solid:
            "Click empty space for a box, or click a sketch profile to extrude it."
        case .sweep:
            "Select the ordered profile and guides, then click the path."
        case .surface:
            "Select at least two ordered profiles, then Preview."
        case .mesh:
            "Select Authored Mesh elements, or make the selected CAD editable."
        case .measure:
            "Click two points to measure the distance between them."
        case .section:
            "Click where the section plane should pass through."
        }
    }

    /// The digit that selects this tool from the Tools menu, if it has one.
    ///
    /// Ten digits are the whole budget a list that may grow can be given, so
    /// the first ten tools carry one in the order the palette shows and the
    /// rest carry none. A tool without a key shows no key anywhere rather
    /// than an invented one.
    public var menuKeyEquivalent: Character? {
        guard let position = Self.allCases.firstIndex(of: self),
              position < 10 else {
            return nil
        }
        return Character(String((position + 1) % 10))
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
