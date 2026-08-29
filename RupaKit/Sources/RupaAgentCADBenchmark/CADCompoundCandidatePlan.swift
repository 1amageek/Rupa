import RupaAgentProtocol

/// Candidate-visible decision for a compound case.
///
/// `CADCandidateAction` deliberately remains the shared single-step wire
/// contract. Compound preparation uses this category-local value to carry an
/// ordered collection until the runner lowers it to one atomic Automation
/// batch. No session, coordinate, expectation, or FeatureID is present here.
struct CADCompoundCandidatePlan: Equatable, Sendable {
    let members: [CADCompoundMemberAction]

    init(members: [CADCompoundMemberAction]) {
        self.members = members
    }
}

protocol CADCompoundCandidateProtocol: Sendable {
    func decide(for context: CADCandidateContext) async throws -> CADCompoundCandidatePlan
}
