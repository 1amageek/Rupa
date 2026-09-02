import RupaAgentProtocol

/// Owns the one benchmark recipe boundary. Implementations produce only
/// transport-safe semantic programs; they never construct graph commands or
/// reserve persistent identities.
protocol CADSemanticProgramPlanning: Sendable {
    func plan(
        for entry: CADCatalogEntry,
        action: CADCandidateAction
    ) throws -> CADSemanticProgramPlan
}
