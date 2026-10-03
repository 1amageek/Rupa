import RupaCore
import RupaRendering
import SwiftCAD

extension WorkspaceFaceEditSession {
    /// Align Surface's badges: each aligned edge with its pair's continuity (Plasticity's markers
    /// on the aligned edges); none for another dialog.
    var continuityBadges: [ViewportContinuityBadge] {
        guard case let .alignSurface(pairs) = kind else { return [] }
        return pairs.indices.map { index in
            ViewportContinuityBadge(target: pairs[index].edge, label: Self.label(of: pairContinuity[index] ?? continuity))
        }
    }

    /// A badge's click: that pair's continuity steps to the next, G0, G1, G2, as its own. False
    /// when `target` is no aligned edge.
    mutating func stepContinuity(of target: SelectionTarget) -> Bool {
        guard case let .alignSurface(pairs) = kind, let index = pairs.firstIndex(where: { $0.edge == target }) else { return false }
        let all = SurfaceContinuityLevel.allCases
        pairContinuity[index] = all[((all.firstIndex(of: pairContinuity[index] ?? continuity) ?? 0) + 1) % all.count]
        return true
    }

    private static func label(of level: SurfaceContinuityLevel) -> String {
        switch level {
        case .positional: "G0"
        case .tangentPlane: "G1"
        case .curvature: "G2"
        }
    }
}
