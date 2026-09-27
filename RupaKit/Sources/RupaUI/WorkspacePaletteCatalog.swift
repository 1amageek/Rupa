/// The commands the Command Palette (F) finds by name, as Plasticity's official pages start them:
/// each runs the same path its key or its Edit menu item runs, so the palette adds no behavior of
/// its own.
struct WorkspacePaletteCatalog: Equatable {
    /// How a palette command runs.
    enum Invocation: Equatable {
        /// The action its key triggers.
        case keyboard(WorkspaceKeyboardAction)
        /// The Edit menu item, which the current selection may leave unavailable.
        case edit(WorkspacePaletteEditCommand)
    }

    struct Command: Equatable, Identifiable {
        var id: String { title }
        var title: String
        /// Other names the official pages give it, which the search also matches.
        var aliases: [String] = []
        /// The key that starts it, shown beside it.
        var shortcut: String?
        var invocation: Invocation
    }

    var commands: [Command]

    static let standard = WorkspacePaletteCatalog(commands: [
        Command(title: "Move", shortcut: "G", invocation: .keyboard(.transformMode(.move))),
        Command(title: "Rotate", shortcut: "R", invocation: .keyboard(.transformMode(.rotate))),
        Command(title: "Scale", shortcut: "S", invocation: .keyboard(.transformMode(.scale))),
        Command(title: "Duplicate", shortcut: "⇧D", invocation: .edit(.duplicate)),
        Command(title: "Mirror", shortcut: "⌥X", invocation: .edit(.mirror)),
        Command(title: "Place", shortcut: "⌃D", invocation: .edit(.place)),
        Command(title: "Copy with Placement", invocation: .edit(.copyWithPlacement)),
        Command(title: "Paste with Placement", invocation: .edit(.pasteWithPlacement)),
        Command(title: "Rectangular Array", invocation: .edit(.rectangularArray)),
        Command(title: "Radial Array", invocation: .edit(.radialArray)),
        Command(title: "Curve Array", invocation: .edit(.curveArray)),
        Command(title: "Bridge", aliases: ["Bridge Curve", "Bridge Vertex"], shortcut: "L", invocation: .keyboard(.bridgeSelection)),
        Command(title: "Cut Curve", aliases: ["Cut"], shortcut: "C", invocation: .keyboard(.beginCutCurve)),
        Command(title: "Trim", shortcut: "T", invocation: .keyboard(.activateTrimCommand)),
        Command(title: "Split Segment", aliases: ["Split Curve At Point"], invocation: .edit(.splitSegment)),
        Command(title: "Slide", aliases: ["Slide Curve CV", "Slide Surface CV"], shortcut: "⇧G", invocation: .keyboard(.activateSlideCommand)),
        Command(title: "Fillet", aliases: ["Fillet Curve", "Fillet Vertex", "Chamfer"], shortcut: "B", invocation: .keyboard(.beginFillet)),
        Command(title: "Join Curves", aliases: ["Join"], shortcut: "J", invocation: .keyboard(.joinSketchCurves)),
        Command(title: "Unjoin Curve", aliases: ["Unjoin"], shortcut: "⌥J", invocation: .keyboard(.unjoinSketchCurve)),
        Command(
            title: "Offset Curve",
            aliases: ["Offset Planar Curve", "Offset Vertex", "Offset Region", "Offset Edge", "Slot"],
            shortcut: "O",
            invocation: .keyboard(.activateOffsetCommand)
        ),
        Command(
            title: "Alternative Duplicate",
            aliases: ["Duplicate Curve and Project", "Project Outline"],
            shortcut: "⌥D",
            invocation: .keyboard(.projectToConstructionPlane)
        ),
        Command(title: "Project", aliases: ["Project Curve Body"], shortcut: "I", invocation: .keyboard(.projectCurvesOntoFace)),
        Command(title: "Complete Edge", invocation: .edit(.completeEdge)),
        Command(title: "Subdivide", invocation: .edit(.subdivide)),
        Command(title: "Insert Knot", aliases: ["Insert CV At Point"], invocation: .edit(.insertKnot)),
        Command(title: "Text", invocation: .edit(.text)),
        Command(title: "Delete Redundant Topology", invocation: .edit(.deleteRedundantTopology)),
        Command(title: "Align Vertex", aliases: ["Align"], invocation: .edit(.alignVertex)),
        Command(title: "Reverse Curve", aliases: ["Reverse"], invocation: .edit(.reverseCurves)),
        Command(title: "Create Instance", aliases: ["Create Curve Instance"], invocation: .edit(.createInstance)),
        Command(title: "Realize Instances", aliases: ["Realize Curve Instances"], invocation: .edit(.realizeInstances)),
        Command(title: "Measure Distance", aliases: ["Measure"], shortcut: "⌃=", invocation: .keyboard(.activateMeasure)),
        Command(title: "Dimension", shortcut: "=", invocation: .keyboard(.activateDimensionCommand)),
        Command(title: "Set Material", shortcut: "M", invocation: .keyboard(.setMaterial)),
    ])

    /// The commands whose title or an alias contains every typed word, ignoring case, in catalog
    /// order; an empty query lists them all.
    func matches(_ query: String) -> [Command] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return commands }
        return commands.filter { command in
            let names = ([command.title] + command.aliases).map { $0.lowercased() }
            return words.allSatisfy { word in names.contains { $0.contains(word) } }
        }
    }
}

/// The Edit menu items the palette reaches, each one of `WorkspaceEditCommands`' closures.
enum WorkspacePaletteEditCommand: Equatable {
    case duplicate, mirror, place, copyWithPlacement, pasteWithPlacement
    case rectangularArray, radialArray, curveArray
    case completeEdge, subdivide, splitSegment, insertKnot
    case createInstance, realizeInstances, reverseCurves, alignVertex, deleteRedundantTopology, text

    /// The closure the Edit menu runs for this item, nil while the selection leaves it unavailable.
    func action(in commands: WorkspaceEditCommands) -> (@MainActor () -> Void)? {
        switch self {
        case .duplicate: commands.duplicate
        case .mirror: commands.mirror
        case .place: commands.place
        case .copyWithPlacement: commands.copyWithPlacement
        case .pasteWithPlacement: commands.pasteWithPlacement
        case .rectangularArray: commands.rectangularArray
        case .radialArray: commands.radialArray
        case .curveArray: commands.curveArray
        case .completeEdge: commands.completeEdge
        case .subdivide: commands.subdivide
        case .splitSegment: commands.splitSegment
        case .insertKnot: commands.insertKnot
        case .createInstance: commands.createInstance
        case .realizeInstances: commands.realizeInstances
        case .reverseCurves: commands.reverseCurves
        case .alignVertex: commands.alignVertex
        case .deleteRedundantTopology: commands.deleteRedundantTopology
        case .text: commands.text
        }
    }
}
