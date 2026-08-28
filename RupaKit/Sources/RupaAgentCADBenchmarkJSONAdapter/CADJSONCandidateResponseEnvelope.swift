import RupaAgentCADBenchmark

public struct CADJSONCandidateResponseEnvelope: Codable, Equatable, Sendable {
    public let schema: String
    public let caseID: CADBenchmarkCaseID
    public let contextFingerprint: String
    public let decision: CADCandidateDecision

    init(
        caseID: CADBenchmarkCaseID,
        context: CADCandidateContext,
        decision: CADCandidateDecision
    ) throws {
        guard context.challenge.id == caseID else {
            throw CADJSONAdapterError.caseMismatch
        }
        try self.init(
            schema: CADJSONAdapterSchema.candidateResponse,
            caseID: caseID,
            contextFingerprint: CADJSONContextFingerprint.value(for: context),
            decision: decision
        )
    }

    public init(
        schema: String,
        caseID: CADBenchmarkCaseID,
        contextFingerprint: String,
        decision: CADCandidateDecision
    ) throws {
        self.schema = schema
        self.caseID = caseID
        self.contextFingerprint = contextFingerprint
        self.decision = decision
        try validate()
    }

    public func validate(
        expectedCaseID: CADBenchmarkCaseID? = nil,
        expectedContextFingerprint: String? = nil
    ) throws {
        guard schema == CADJSONAdapterSchema.candidateResponse else {
            throw CADJSONAdapterError.unsupportedSchema
        }
        do {
            try caseID.validate()
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        try CADJSONContextFingerprint.validate(contextFingerprint)
        if let expectedCaseID, expectedCaseID != caseID {
            throw CADJSONAdapterError.caseMismatch
        }
        if let expectedContextFingerprint, expectedContextFingerprint != contextFingerprint {
            throw CADJSONAdapterError.fingerprintMismatch
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case caseID
        case contextFingerprint
        case decision
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(caseID, forKey: .caseID)
        try container.encode(contextFingerprint, forKey: .contextFingerprint)
        try container.encode(decision, forKey: .decision)
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys>
        do {
            container = try decoder.container(keyedBy: CodingKeys.self)
            self.schema = try container.decode(String.self, forKey: .schema)
            self.caseID = try container.decode(CADBenchmarkCaseID.self, forKey: .caseID)
            self.contextFingerprint = try container.decode(String.self, forKey: .contextFingerprint)
            do {
                self.decision = try container.decode(CADCandidateDecision.self, forKey: .decision)
            } catch {
                throw CADJSONAdapterError.invalidDecision
            }
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        try validate()
    }
}
