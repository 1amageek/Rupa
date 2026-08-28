public protocol CADCandidateProtocol: Sendable {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision
}
