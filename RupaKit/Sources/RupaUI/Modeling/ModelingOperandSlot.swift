/// A pick slot of an operation's dialog, as Plasticity's dialogs show them ("Select boundaries",
/// "Select guides", "Select target bodies"): the operands put in a slot take that slot's role,
/// whatever order they were selected in.
enum ModelingOperandSlot: String, CaseIterable, Identifiable, Sendable {
    case boundaries = "Boundaries"
    case guides = "Guides"
    /// Pipe's custom profile, a region or a face.
    case profile = "Profile"
    /// Pipe's curves or edges, one pipe along each.
    case paths = "Curves"
    case section = "Section"
    case spine = "Spine"
    /// The solids a Boolean combines the result with.
    case targetBodies = "Target bodies"

    var id: Self { self }

    /// The slot's prompt in the dialog.
    var prompt: String { "Select \(rawValue.lowercased())" }
}
