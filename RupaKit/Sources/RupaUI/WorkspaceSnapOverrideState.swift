import RupaCore
import RupaRendering

struct WorkspaceSnapOverrideState: Equatable {
    var hoveredCandidateKind: SnapCandidateKind?
    var suppressedCandidateKinds: Set<SnapCandidateKind> = []

    mutating func updateHoveredCandidateKind(_ kind: SnapCandidateKind?) {
        hoveredCandidateKind = kind
    }

    mutating func beginCandidateKindBypass() -> Bool {
        guard let hoveredCandidateKind else {
            return false
        }
        return suppressedCandidateKinds.insert(hoveredCandidateKind).inserted
    }

    mutating func endCandidateKindBypass() {
        suppressedCandidateKinds.removeAll()
    }

    func objectTargetingOverride(
        for modifierFlags: ViewportInputModifierFlags
    ) -> SnapObjectTargetingOverride {
        modifierFlags.containsControl ? .forceEnabled : .none
    }
}
