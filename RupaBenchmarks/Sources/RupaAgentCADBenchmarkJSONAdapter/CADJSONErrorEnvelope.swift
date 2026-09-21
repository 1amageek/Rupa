import RupaAgentCADBenchmark

public struct CADJSONErrorEnvelope: Codable, Equatable, Sendable {
    public let schema: String
    public let code: CADJSONErrorCode
    public let caseID: CADBenchmarkCaseID?
    public let message: String

    public init(code: CADJSONErrorCode, caseID: CADBenchmarkCaseID? = nil) throws {
        self.schema = CADJSONAdapterSchema.error
        self.code = code
        self.caseID = caseID
        self.message = code.stableMessage
        try validate()
    }

    public init(error: Error, caseID: CADBenchmarkCaseID? = nil) throws {
        if let error = error as? CADJSONAdapterError {
            try self.init(code: error.code, caseID: caseID)
        } else if let error = error as? CADActivatedCaseExecutorError {
            let code: CADJSONErrorCode
            switch error {
            case .inactiveCase:
                code = .inactiveCase
            case .candidateFailure:
                code = .candidateFailure
            case .catalogFailure, .invalidResult:
                code = .infrastructureFailure
            }
            try self.init(code: code, caseID: caseID)
        } else if error is CancellationError {
            try self.init(code: .cancellation, caseID: caseID)
        } else {
            try self.init(code: .infrastructureFailure, caseID: caseID)
        }
    }

    public func validate() throws {
        guard schema == CADJSONAdapterSchema.error else {
            throw CADJSONAdapterError.unsupportedSchema
        }
        if let caseID {
            do {
                try caseID.validate()
            } catch {
                throw CADJSONAdapterError.malformedJSON
            }
        }
        guard message == code.stableMessage else {
            throw CADJSONAdapterError.malformedJSON
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case code
        case caseID
        case message
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(caseID, forKey: .caseID)
        try container.encode(message, forKey: .message)
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys>
        do {
            container = try decoder.container(keyedBy: CodingKeys.self)
            let schema = try container.decode(String.self, forKey: .schema)
            let code = try container.decode(CADJSONErrorCode.self, forKey: .code)
            let caseID = try container.decodeIfPresent(CADBenchmarkCaseID.self, forKey: .caseID)
            let message = try container.decode(String.self, forKey: .message)
            self.schema = schema
            self.code = code
            self.caseID = caseID
            self.message = message
        } catch let error as CADJSONAdapterError {
            throw error
        } catch {
            throw CADJSONAdapterError.malformedJSON
        }
        try validate()
    }
}
