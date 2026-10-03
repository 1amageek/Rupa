import RupaCore
import SwiftCAD

/// The dialog of an imprinting command while it runs, on what was selected when it started:
/// Imprint Curve Body (curves onto one object: Normal, or Vector along the typed direction with
/// Bidirectional and Hide occlusion, and Completion), Imprint Body Body (a tool onto a target,
/// with Complete target, Imprint tool and Complete tool), Isoparam (a face's U or V lines: Count,
/// Param for a single line, and Subdivide) and Untrim (a face's untrimmed sheet, with Keep
/// edges). OK, Return or right-click applies; Escape ends it without a change.
///
/// Imprint takes its operands as clicks while it runs, as Plasticity's slots do: started on
/// curves alone, a body alone or nothing (`picking`), the first body clicked is the target and
/// then curves, or a second body as the tool, complete it; once complete, clicked curves go on or
/// off and a clicked body other than the target becomes the tool.
struct WorkspaceImprintSession: Equatable {
    /// This dialog, apart from the one the command starts next (`WorkspaceDialogSubmissions`).
    let instance = WorkspaceDialogInstance()

    enum Kind: Equatable {
        /// Imprint before its target and what it imprints are both known.
        case picking(target: SceneNodeID?, curves: [SelectionTarget])
        case curves(target: SceneNodeID, curves: [SelectionTarget])
        case bodies(target: SceneNodeID, tool: SceneNodeID)
        case isoparam(face: SelectionTarget)
        case untrim(face: SelectionTarget)
    }

    enum Method: String, CaseIterable, Equatable {
        case normal
        case vector

        var title: String {
            switch self {
            case .normal: "Normal"
            case .vector: "Vector"
            }
        }
    }

    private(set) var kind: Kind
    var method: Method = .normal
    var vectorX = 0.0
    var vectorY = 0.0
    var vectorZ = -1.0
    var isBidirectional = false
    var hidesOcclusion = false
    var completion: ImprintCompletion = .none
    var imprintsTool = false
    var toolCompletion: ImprintCompletion = .none
    var direction: SurfaceParameterDirection = .u
    /// How many lines Isoparam imprints, evenly spaced; a single line lies at `parameter`.
    var count = 1
    var parameter = 0.5
    var subdividesControlNet = false
    var keepsEdges = false

    init(kind: Kind) {
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .picking, .curves, .bodies: "Imprint"
        case .isoparam: "Isoparam"
        case .untrim: "Untrim"
        }
    }

    /// The fractions of the face's extent the lines lie at.
    var fractions: [Double] {
        count <= 1 ? [min(max(parameter, 0.001), 0.999)] : (1...count).map { Double($0) / Double(count + 1) }
    }

    /// Shift-wheel: Isoparam's Count, from 1 to 64.
    mutating func stepCount(by delta: Int) {
        count = min(max(count + delta, 1), 64)
    }

    /// Tab's toggle: Isoparam's direction, or Untrim's Keep edges.
    mutating func toggle() {
        switch kind {
        case .isoparam: direction = direction == .u ? .v : .u
        case .untrim: keepsEdges.toggle()
        case .picking, .curves, .bodies: break
        }
    }

    /// Whether the viewport's clicks pick Imprint's operands.
    var takesPicks: Bool {
        switch kind {
        case .picking, .curves, .bodies: true
        case .isoparam, .untrim: false
        }
    }

    /// A clicked solid or sheet: the target while there is none, else the tool (a body imprinted
    /// onto the target, in place of any curves).
    mutating func pick(body: SceneNodeID) {
        switch kind {
        case let .picking(nil, curves):
            kind = curves.isEmpty ? .picking(target: body, curves: []) : .curves(target: body, curves: curves)
        case let .picking(target?, _) where target != body:
            kind = .bodies(target: target, tool: body)
        case let .curves(target, _) where target != body:
            kind = .bodies(target: target, tool: body)
        case let .bodies(target, _) where target != body:
            kind = .bodies(target: target, tool: body)
        case .picking, .curves, .bodies, .isoparam, .untrim:
            break
        }
    }

    /// A clicked curve (a sketch or a curve object): on, or off when already imprinted.
    mutating func pick(curve: SelectionTarget) {
        func toggled(_ curves: [SelectionTarget]) -> [SelectionTarget] {
            curves.contains(curve) ? curves.filter { $0 != curve } : curves + [curve]
        }
        switch kind {
        case let .picking(target, curves):
            let next = toggled(curves)
            if let target, next.isEmpty == false {
                kind = .curves(target: target, curves: next)
            } else {
                kind = .picking(target: target, curves: next)
            }
        case let .curves(target, curves):
            let next = toggled(curves)
            kind = next.isEmpty ? .picking(target: target, curves: []) : .curves(target: target, curves: next)
        case let .bodies(target, _):
            kind = .curves(target: target, curves: [curve])
        case .isoparam, .untrim:
            break
        }
    }

    /// What OK still needs, as the status bar says it; nil once the command can run.
    var missingInput: String? {
        guard case let .picking(target, _) = kind else { return nil }
        return target == nil
            ? "Imprint: click the solid or sheet to imprint on."
            : "Imprint: click the curves, or a body as the tool, to imprint."
    }

    /// The command OK submits, nil while Imprint still picks. A Normal curve imprint takes each
    /// point to its nearest face; a Vector one sweeps along the typed direction, in the world.
    func command() -> EditorCommand? {
        switch kind {
        case .picking:
            return nil
        case let .curves(target, curves):
            let projection: ImprintProjection = method == .normal
                ? .normal
                : .vector(direction: Vector3D(x: vectorX, y: vectorY, z: vectorZ), bidirectional: isBidirectional, hidesOcclusion: hidesOcclusion)
            return .imprintCurves(name: "Imprint", target: target, curves: curves, projection: projection, completion: completion)
        case let .bodies(target, tool):
            return .imprintBodies(
                name: "Imprint", target: target, tool: tool, targetCompletion: completion,
                imprintsTool: imprintsTool, toolCompletion: toolCompletion
            )
        case let .isoparam(face):
            return .isoparam(name: "Isoparam", face: face, direction: direction, fractions: fractions, subdividesControlNet: subdividesControlNet)
        case let .untrim(face):
            return .untrimFace(name: "Untrim", face: face, keepsEdges: keepsEdges)
        }
    }
}
