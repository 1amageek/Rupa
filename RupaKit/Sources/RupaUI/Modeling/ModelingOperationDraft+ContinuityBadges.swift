import RupaCore
import RupaRendering

extension ModelingOperationDraft {
    /// The viewport badges of the boundaries whose continuity the dialog sets (Plasticity's round
    /// badges): Square's sides and XNURBS's boundary edges each with its own continuity, and the
    /// hole edges of Patch with the hole's one continuity. Only edges of bodies carry a badge: a
    /// curve has no face to be continuous with. Refit Face's faces carry none (their sides keep the
    /// one continuity of its dialog).
    var continuityBadges: [ViewportContinuityBadge] {
        func isEdge(_ target: SelectionTarget) -> Bool {
            if case .edge = target.component { return true }
            return false
        }
        switch kind {
        case .square where refitsFaces == false:
            return targets.filter(isEdge).map { ViewportContinuityBadge(target: $0, label: squareContinuity(of: $0).rawValue) }
        case .xnurbs:
            return targets.filter { isEdge($0) && xnurbsGuideNodeIDs.contains($0.sceneNodeID) == false }
                .map { ViewportContinuityBadge(target: $0, label: xnurbsContinuity(of: $0).rawValue) }
        case .patch:
            return patchHoleEdges.map { ViewportContinuityBadge(target: $0, label: patchContinuity.rawValue) }
        default:
            return []
        }
    }

    /// A badge's click: the boundary's continuity steps to the next (Square G0, G1, G2, Free;
    /// XNURBS G0, G1, G2), as its own. Patch fills its hole with one continuity, so a click on any
    /// of its edges steps the hole's, as Tab does. False when `target` carries no badge.
    mutating func stepContinuity(of target: SelectionTarget) -> Bool {
        guard continuityBadges.contains(where: { $0.target == target }) else { return false }
        switch kind {
        case .square:
            let all = SquareContinuityChoice.allCases
            squareSideContinuity[target] = all[((all.firstIndex(of: squareContinuity(of: target)) ?? 0) + 1) % all.count]
        case .xnurbs:
            let all = LoftContinuityChoice.allCases
            xnurbsEdgeContinuity[target] = all[((all.firstIndex(of: xnurbsContinuity(of: target)) ?? 0) + 1) % all.count]
        case .patch:
            cyclePatchContinuity()
        default:
            return false
        }
        return true
    }
}
