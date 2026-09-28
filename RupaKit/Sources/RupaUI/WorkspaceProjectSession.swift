import RupaCore
import SwiftCAD

/// Project Curve Body's dialog while it runs, on the curves and the one face selected when I
/// started it. Normal projects along the active construction plane's +Z; Vector along the typed
/// direction, both ways when Bidirectional is on. OK, Return or right-click projects; Escape ends
/// it without a change.
struct WorkspaceProjectSession: Equatable {
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

    let curves: [SelectionTarget]
    let face: SelectionTarget
    var method: Method = .normal
    var vectorX = 0.0
    var vectorY = 0.0
    var vectorZ = -1.0
    /// Only Vector takes it.
    var isBidirectional = false

    init?(curves: [SelectionTarget], face: SelectionTarget) {
        guard !curves.isEmpty else { return nil }
        self.curves = curves
        self.face = face
    }

    /// The command OK submits; Normal takes the construction plane's normal.
    func command(constructionPlaneNormal: Vector3D) -> EditorCommand {
        switch method {
        case .normal:
            .projectCurvesAlongDirection(targets: curves, face: face, direction: constructionPlaneNormal, bidirectional: false)
        case .vector:
            .projectCurvesAlongDirection(
                targets: curves, face: face,
                direction: Vector3D(x: vectorX, y: vectorY, z: vectorZ),
                bidirectional: isBidirectional
            )
        }
    }
}
