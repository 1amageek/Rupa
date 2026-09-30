import RupaCore
import SwiftCAD

/// The dialog of an imprinting command while it runs, on what was selected when it started:
/// Imprint Curve Body (curves onto one object: Normal, or Vector along the typed direction with
/// Bidirectional and Hide occlusion, and Completion), Imprint Body Body (a tool onto a target,
/// with Complete target, Imprint tool and Complete tool), Isoparam (a face's U or V lines: Count,
/// Param for a single line, and Subdivide) and Untrim (a face's untrimmed sheet, with Keep
/// edges). OK, Return or right-click applies; Escape ends it without a change.
struct WorkspaceImprintSession: Equatable {
    /// This dialog, apart from the one the command starts next (`WorkspaceDialogSubmissions`).
    let instance = WorkspaceDialogInstance()

    enum Kind: Equatable {
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

    let kind: Kind
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
        case .curves, .bodies: "Imprint"
        case .isoparam: "Isoparam"
        case .untrim: "Untrim"
        }
    }

    /// The fractions of the face's extent the lines lie at.
    var fractions: [Double] {
        count <= 1 ? [min(max(parameter, 0.001), 0.999)] : (1...count).map { Double($0) / Double(count + 1) }
    }

    /// Tab's toggle: Isoparam's direction, or Untrim's Keep edges.
    mutating func toggle() {
        switch kind {
        case .isoparam: direction = direction == .u ? .v : .u
        case .untrim: keepsEdges.toggle()
        case .curves, .bodies: break
        }
    }

    /// The command OK submits. A Normal curve imprint takes each point to its nearest face; a
    /// Vector one sweeps along the typed direction, in the world.
    func command() -> EditorCommand {
        switch kind {
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
