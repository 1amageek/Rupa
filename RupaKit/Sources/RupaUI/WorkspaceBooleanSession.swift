import RupaCore
import SwiftCAD

/// Boolean's dialog while it runs: the target bodies, the tool bodies, which of the two a click on
/// a body adds to or removes from, the operation, Keep Tools and each side's material.
///
/// Q starts it on the selected bodies: with several selected, the last one is the tool and the
/// others are the targets; with one, it is the target and the clicks pick tools. While it runs Q
/// unions, W subtracts, Shift-E intersects, Shift-Q slices, T keeps the tools, G, R and S move,
/// rotate and scale the tools, Return or right-click combines and Escape ends it.
struct WorkspaceBooleanSession: Equatable {
    enum Role: Equatable {
        case targets
        case tools
    }

    private(set) var targets: [SceneNodeID]
    private(set) var tools: [SceneNodeID]
    /// Which list a clicked body joins.
    var picking: Role
    private(set) var operation: BooleanOperation
    var keepTools = false
    /// How each side's material is taken; a Region takes none.
    var targetMaterial: BooleanMaterial = .default
    var toolMaterial: BooleanMaterial = .default

    init(selectedBodies: [SceneNodeID], operation: BooleanOperation = .union) {
        switch selectedBodies.count {
        case 0:
            targets = []
            tools = []
            picking = .targets
        case 1:
            targets = selectedBodies
            tools = []
            picking = .tools
        default:
            targets = Array(selectedBodies.dropLast())
            tools = [selectedBodies[selectedBodies.count - 1]]
            picking = .tools
        }
        self.operation = operation
    }

    /// Whether both lists hold a body, so the Boolean can run.
    var canApply: Bool {
        !targets.isEmpty && !tools.isEmpty
    }

    /// Every body the dialog holds, which the viewport shows selected.
    var operands: [SceneNodeID] {
        targets + tools
    }

    /// Whether the materials apply: a Region divides space by faces alone.
    var takesMaterials: Bool {
        operation != .region
    }

    var title: String {
        switch operation {
        case .union: "Union"
        case .difference: "Difference"
        case .intersect: "Intersect"
        case .slice: "Slice"
        case .region: "Region"
        }
    }

    var prompt: String {
        switch picking {
        case .targets: "Boolean \(title): click the target bodies, Return combines."
        case .tools: "Boolean \(title): click the tool bodies, Return combines."
        }
    }

    /// The materials a side can take, in the order the dialog lists them.
    static let materials: [BooleanMaterial] = [.default, .empty, .inside, .outside]

    static func title(of material: BooleanMaterial) -> String {
        switch material {
        case .default: "Default"
        case .empty: "Empty"
        case .inside: "Inside"
        case .outside: "Outside"
        }
    }

    /// Chooses the operation; a Region drops the materials it cannot take.
    mutating func setOperation(_ operation: BooleanOperation) {
        self.operation = operation
        if operation == .region {
            targetMaterial = .default
            toolMaterial = .default
        }
    }

    /// A clicked body joins the list being picked, or leaves it when it is already there; a body is
    /// never both a target and a tool.
    mutating func toggle(_ body: SceneNodeID) {
        switch picking {
        case .targets:
            if let index = targets.firstIndex(of: body) {
                targets.remove(at: index)
            } else {
                tools.removeAll { $0 == body }
                targets.append(body)
            }
        case .tools:
            if let index = tools.firstIndex(of: body) {
                tools.remove(at: index)
            } else {
                targets.removeAll { $0 == body }
                tools.append(body)
            }
        }
    }

    /// The Boolean of the dialog's bodies, each combined where it is displayed.
    func command(in document: DesignDocument) throws -> EditorCommand {
        guard canApply else {
            throw EditorError(code: .commandInvalid, message: "Boolean needs at least one target body and one tool body.")
        }
        func feature(of nodeID: SceneNodeID) throws -> FeatureID {
            guard let node = document.productMetadata.sceneNodes[nodeID], !node.isLocked,
                  node.reference?.kind == .body, let featureID = node.reference?.featureID else {
                throw EditorError(code: .commandInvalid, message: "Boolean operands must be editable body objects.")
            }
            return featureID
        }
        return .createBoolean(
            name: "Boolean",
            targets: try targets.map { BooleanTargetReference(featureID: try feature(of: $0)) },
            tools: try tools.map { BooleanToolReference(featureID: try feature(of: $0)) },
            operation: operation,
            keepTools: keepTools,
            targetMaterial: targetMaterial,
            toolMaterial: toolMaterial
        )
    }
}
