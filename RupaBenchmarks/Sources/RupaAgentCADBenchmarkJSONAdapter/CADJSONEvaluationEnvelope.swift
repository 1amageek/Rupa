import RupaAgentCADBenchmark

public struct CADJSONEvaluationEnvelope: Codable, Equatable, Sendable {
    public let schema: String
    public let caseID: CADBenchmarkCaseID
    public let contextFingerprint: String
    public let result: CADCaseResult?
    public let error: CADJSONErrorEnvelope?

    init(
        caseID: CADBenchmarkCaseID,
        contextFingerprint: String,
        result: CADCaseResult
    ) throws {
        self.schema = CADJSONAdapterSchema.evaluation
        self.caseID = caseID
        self.contextFingerprint = contextFingerprint
        self.result = result
        self.error = nil
        try validate()
    }

    init(
        caseID: CADBenchmarkCaseID,
        contextFingerprint: String,
        error: CADJSONErrorEnvelope
    ) throws {
        self.schema = CADJSONAdapterSchema.evaluation
        self.caseID = caseID
        self.contextFingerprint = contextFingerprint
        self.result = nil
        self.error = error
        try validate()
    }

    public func validate() throws {
        guard schema == CADJSONAdapterSchema.evaluation else {
            throw CADJSONAdapterError.unsupportedSchema
        }
        do {
            try caseID.validate()
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        try CADJSONContextFingerprint.validate(contextFingerprint)
        guard (result == nil) != (error == nil) else {
            throw CADJSONAdapterError.malformedJSON
        }
        if let result {
            guard result.id == caseID else {
                throw CADJSONAdapterError.caseMismatch
            }
            do {
                try result.validate()
            } catch {
                throw CADJSONAdapterError.malformedJSON
            }
        }
        if let error {
            guard error.caseID == caseID else {
                throw CADJSONAdapterError.caseMismatch
            }
            try error.validate()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case caseID
        case contextFingerprint
        case result
        case error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(caseID, forKey: .caseID)
        try container.encode(contextFingerprint, forKey: .contextFingerprint)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys>
        do {
            container = try decoder.container(keyedBy: CodingKeys.self)
            self.schema = try container.decode(String.self, forKey: .schema)
            self.caseID = try container.decode(CADBenchmarkCaseID.self, forKey: .caseID)
            self.contextFingerprint = try container.decode(String.self, forKey: .contextFingerprint)
            self.result = try container.decodeIfPresent(CADCaseResult.self, forKey: .result)
            self.error = try container.decodeIfPresent(CADJSONErrorEnvelope.self, forKey: .error)
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        try validate()
    }
}
