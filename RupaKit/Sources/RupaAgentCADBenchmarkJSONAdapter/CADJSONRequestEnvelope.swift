import RupaAgentCADBenchmark

public struct CADJSONRequestEnvelope: Codable, Equatable, Sendable {
    public let schema: String
    public let caseID: CADBenchmarkCaseID
    public let contextFingerprint: String
    public let context: CADCandidateContext

    init(caseID: CADBenchmarkCaseID, context: CADCandidateContext) throws {
        let fingerprint = try CADJSONContextFingerprint.value(for: context)
        try self.init(
            schema: CADJSONAdapterSchema.request,
            caseID: caseID,
            contextFingerprint: fingerprint,
            context: context
        )
    }

    init(
        schema: String,
        caseID: CADBenchmarkCaseID,
        contextFingerprint: String,
        context: CADCandidateContext
    ) throws {
        self.schema = schema
        self.caseID = caseID
        self.contextFingerprint = contextFingerprint
        self.context = context
        try validate()
    }

    public func validate(
        expectedCaseID: CADBenchmarkCaseID? = nil,
        expectedContextFingerprint: String? = nil
    ) throws {
        guard schema == CADJSONAdapterSchema.request else {
            throw CADJSONAdapterError.unsupportedSchema
        }
        do {
            try caseID.validate()
            try context.validate()
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        guard context.challenge.id == caseID else {
            throw CADJSONAdapterError.caseMismatch
        }
        try CADJSONContextFingerprint.validate(contextFingerprint)
        let computed = try CADJSONContextFingerprint.value(for: context)
        guard contextFingerprint == computed else {
            throw CADJSONAdapterError.fingerprintMismatch
        }
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
        case context
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(caseID, forKey: .caseID)
        try container.encode(contextFingerprint, forKey: .contextFingerprint)
        try container.encode(context, forKey: .context)
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys>
        do {
            container = try decoder.container(keyedBy: CodingKeys.self)
            self.schema = try container.decode(String.self, forKey: .schema)
            self.caseID = try container.decode(CADBenchmarkCaseID.self, forKey: .caseID)
            self.contextFingerprint = try container.decode(String.self, forKey: .contextFingerprint)
            self.context = try container.decode(CADCandidateContext.self, forKey: .context)
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        try validate()
    }
}
