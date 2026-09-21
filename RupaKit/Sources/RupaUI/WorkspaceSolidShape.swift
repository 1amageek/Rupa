import RupaCore

/// The primitive placed by the shared Solid canvas tool.
enum WorkspaceSolidShape: String, CaseIterable, Identifiable, Sendable {
    case box = "Box"
    case sphere = "Sphere"
    case cylinder = "Cylinder"

    var id: Self { self }
    var systemImage: String {
        switch self {
        case .box: "cube"
        case .sphere: "globe"
        case .cylinder: "cylinder"
        }
    }
    var activationPrompt: String {
        switch self {
        case .box: ModelingTool.solid.activationPrompt
        case .sphere: "Click to place a sphere, or drag from its center to set its radius."
        case .cylinder: "Click to place a cylinder, or drag from its base center to set its radius."
        }
    }
}
