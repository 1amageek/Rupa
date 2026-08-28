import RupaAgentCADBenchmark

struct CADJSONCandidate: CADCandidateProtocol, Sendable {
    private let response: CADJSONCandidateResponseEnvelope

    init(response: CADJSONCandidateResponseEnvelope) throws {
        try response.validate()
        self.response = response
    }

    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        try response.validate()
        do {
            try context.validate()
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        guard response.caseID == context.challenge.id else {
            throw CADJSONAdapterError.caseMismatch
        }
        let fingerprint = try CADJSONContextFingerprint.value(for: context)
        guard response.contextFingerprint == fingerprint else {
            throw CADJSONAdapterError.fingerprintMismatch
        }
        return response.decision
    }
}
