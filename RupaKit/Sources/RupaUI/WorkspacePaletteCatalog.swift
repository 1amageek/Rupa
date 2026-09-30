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
        Command(title: "Boolean", aliases: ["Union", "Difference", "Intersect", "Slice", "Region"], shortcut: "Q", invocation: .keyboard(.beginBoolean)),
        Command(title: "Cut", shortcut: "C", invocation: .keyboard(.beginBodyCut)),
        Command(title: "Cut Curve", shortcut: "C", invocation: .keyboard(.beginCutCurve)),
        Command(title: "Trim", shortcut: "T", invocation: .keyboard(.activateTrimCommand)),
        Command(title: "Split Segment", aliases: ["Split Curve At Point"], invocation: .edit(.splitSegment)),
        Command(title: "Slide", aliases: ["Slide Curve CV", "Slide Surface CV"], shortcut: "⇧G", invocation: .keyboard(.activateSlideCommand)),
        Command(title: "Fillet", aliases: ["Fillet Curve", "Fillet Vertex", "Chamfer"], shortcut: "B", invocation: .keyboard(.beginFillet)),
        Command(title: "Join", aliases: ["Join Curves", "Join Sheets"], shortcut: "J", invocation: .keyboard(.join)),
        Command(
            title: "Unjoin", aliases: ["Unjoin Curve", "Unjoin Faces", "Unjoin Shells"], shortcut: "⌥J",
            invocation: .keyboard(.unjoin)
        ),
        Command(
            title: "Offset Curve",
            aliases: ["Offset Planar Curve", "Offset Vertex", "Offset Region", "Offset Edge", "Slot"],
            shortcut: "O",
            invocation: .keyboard(.activateOffsetCommand)
        ),
        Command(
            title: "Alternative Duplicate",
            aliases: ["Duplicate Curve and Project", "Project Outline", "Duplicate Faces"],
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
        Command(title: "Reverse", aliases: ["Reverse Curve", "Reverse Sheet"], invocation: .edit(.reverse)),
        Command(title: "Raise Degree", aliases: ["Raise Curve Degree", "Raise Surface Degree"], shortcut: "⇧S", invocation: .edit(.raiseDegree)),
        Command(title: "Find Boundary Edges", invocation: .edit(.findBoundaryEdges)),
        Command(title: "Imprint", aliases: ["Imprint Curve Body", "Imprint Body Body"], shortcut: "⇧I", invocation: .keyboard(.beginImprint)),
        Command(title: "Isoparam", shortcut: "⌃R", invocation: .keyboard(.beginIsoparam)),
        Command(title: "Untrim", shortcut: "⌥T", invocation: .keyboard(.beginUntrim)),
        Command(title: "Push Face", aliases: ["Offset Face"], invocation: .keyboard(.beginPushFace)),
        Command(title: "Draft Face", invocation: .keyboard(.beginDraftFace)),
        Command(title: "Match Face", invocation: .keyboard(.beginMatchFace)),
        Command(title: "Remove Fillets From Shell", aliases: ["Remove Fillets"], invocation: .keyboard(.beginRemoveFillets)),
        Command(title: "Hollow", invocation: .keyboard(.beginHollow)),
        Command(title: "Extend", aliases: ["Extend Sheet", "Extend Curve"], invocation: .keyboard(.beginExtend)),
        Command(title: "Thicken", aliases: ["Thicken Face"], invocation: .keyboard(.beginThicken)),
        Command(title: "Toggle Curvature", aliases: ["Toggle Surface Curvature", "Curvature Comb"], invocation: .edit(.toggleCurvature)),
        Command(title: "Convert Vertex", invocation: .edit(.convertVertex)),
        Command(title: "Rebuild", aliases: ["Rebuild Curve"], invocation: .edit(.rebuild)),
        Command(title: "Deform", aliases: ["Deform Curve", "Deform Solid and Sheet"], invocation: .edit(.deform)),
        Command(title: "Create Outline", invocation: .edit(.createOutline)),
        Command(title: "Create Instance", aliases: ["Create Curve Instance", "Create Solid and Sheet Instance"], invocation: .edit(.createInstance)),
        Command(title: "Realize Instances", aliases: ["Realize Curve Instances", "Realize Solid and Sheet Instances"], invocation: .edit(.realizeInstances)),
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
    case createInstance, realizeInstances, reverse, alignVertex, deleteRedundantTopology, text
    case raiseDegree, findBoundaryEdges, toggleCurvature, convertVertex, rebuild, deform, createOutline

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
        case .reverse: commands.reverse
        case .alignVertex: commands.alignVertex
        case .deleteRedundantTopology: commands.deleteRedundantTopology
        case .text: commands.text
        case .raiseDegree: commands.raiseDegree
        case .findBoundaryEdges: commands.findBoundaryEdges
        case .toggleCurvature: commands.toggleCurvature
        case .convertVertex: commands.convertVertex
        case .rebuild: commands.rebuild
        case .deform: commands.deform
        case .createOutline: commands.createOutline
        }
    }
}
