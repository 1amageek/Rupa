import RupaCore
import RupaRendering
import SwiftCAD

/// Cut's dialog while it runs: the bodies to cut, the curves and faces cutting them, which of the
/// two a click adds to or removes from, Extend and the view direction.
///
/// C starts it when bodies are selected: the selected bodies are the targets, and selected curve
/// objects and faces the cutters. While it runs C switches to Cut Curve, S cuts along the view
/// instead of each curve's plane normal, E extends the curve cutters, Return or right-click cuts
/// and Escape ends it.
struct WorkspaceBodyCutSession: Equatable {
    enum Role: Equatable {
        case targets
        case cutters
    }

    private(set) var targets: [SceneNodeID]
    private(set) var cutters: [CutCutter]
    /// Which list a click joins.
    var picking: Role
    /// Extend: each curve cutter reaches through the targets.
    var extendsCurves = false
    /// The view direction curve cutters are extruded along; `nil` extrudes each along its plane's
    /// normal.
    var viewDirection: Vector3D?

    init(targets: [SceneNodeID], cutters: [CutCutter]) {
        self.targets = targets
        self.cutters = cutters
        picking = targets.isEmpty ? .targets : .cutters
    }

    /// The selection split into bodies to cut and cutters: body objects are targets, curve objects
    /// (and the sketches of selected sketch curves) and faces are cutters.
    init(selection: [SelectionTarget], in document: DesignDocument) {
        var targets: [SceneNodeID] = []
        var cutters: [CutCutter] = []
        for target in selection {
            guard let node = document.productMetadata.sceneNodes[target.sceneNodeID] else { continue }
            switch target.component {
            case .face:
                cutters.append(.face(target))
            case .object, .sketchEntity:
                if node.reference?.kind == .body, target.component == .object {
                    if !targets.contains(node.id) { targets.append(node.id) }
                } else if Self.isCurveObject(node, in: document), !cutters.contains(.curve(node.id)) {
                    cutters.append(.curve(node.id))
                }
            default:
                continue
            }
        }
        self.init(targets: targets, cutters: cutters)
    }

    /// Whether `node` shows a feature with curve output, which a curve cutter extrudes.
    static func isCurveObject(_ node: SceneNode, in document: DesignDocument) -> Bool {
        guard let featureID = node.reference?.featureID else { return false }
        return document.cadDocument.designGraph.nodes[featureID]?.outputs.contains { $0.role == .curve } == true
    }

    /// What a click reaches whatever the selection scope: bodies while picking targets; curves
    /// and faces while picking cutters.
    var viewportHitPolicy: ViewportSelectionHitPolicy {
        picking == .targets ? .object : .all
    }

    /// Whether both lists hold something, so the cut can run.
    var canCut: Bool {
        !targets.isEmpty && !cutters.isEmpty
    }

    var options: CutOptions {
        CutOptions(extendsCurves: extendsCurves, direction: viewDirection)
    }

    var prompt: String {
        switch picking {
        case .targets: "Cut: click the bodies to cut, Return cuts."
        case .cutters: "Cut: click the cutting curves or faces, Return cuts, E extends the curves."
        }
    }

    /// A clicked body joins or leaves the targets.
    mutating func toggle(target body: SceneNodeID) {
        if let index = targets.firstIndex(of: body) {
            targets.remove(at: index)
        } else {
            targets.append(body)
        }
    }

    /// A clicked curve or face joins or leaves the cutters.
    mutating func toggle(cutter: CutCutter) {
        if let index = cutters.firstIndex(of: cutter) {
            cutters.remove(at: index)
        } else {
            cutters.append(cutter)
        }
    }

    /// The cut of the dialog's targets by its cutters.
    func command() throws -> EditorCommand {
        guard canCut else {
            throw EditorError(code: .commandInvalid, message: "Cut needs at least one body to cut and one cutter.")
        }
        return .cut(name: "Cut", targets: targets, cutters: cutters, options: options)
    }
}
