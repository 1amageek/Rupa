import RupaCoreTypes
import RupaDomainFoundation

public struct AgentSemanticDirectRequest: Codable, Equatable, Sendable {
    public struct ArgumentEntry: Codable, Equatable, Sendable {
        public let name: String
        public let value: AgentSemanticDirectArgument

        private enum CodingKeys: String, CodingKey { case name, value }

        public init(name: String, value: AgentSemanticDirectArgument) {
            self.name = name
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["name", "value"])
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                value: try container.decode(AgentSemanticDirectArgument.self, forKey: .value)
            )
        }
    }

    public let schemaVersion: AgentSemanticSchemaVersion
    public let operationID: DomainCapabilityID
    public let operationVersion: AgentSemanticOperationVersion
    public let arguments: [ArgumentEntry]
    public let requestedOutputs: [String]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case operationID
        case operationVersion
        case arguments
        case requestedOutputs
    }

    public init(
        schemaVersion: AgentSemanticSchemaVersion,
        operationID: DomainCapabilityID,
        operationVersion: AgentSemanticOperationVersion,
        arguments: [ArgumentEntry] = [],
        requestedOutputs: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.operationVersion = operationVersion
        self.arguments = arguments
        self.requestedOutputs = requestedOutputs
    }

    public init(_ value: SemanticDirectRequest) throws {
        self.init(
            schemaVersion: AgentSemanticSchemaVersion(value.schemaVersion),
            operationID: value.invocation.operationID,
            operationVersion: AgentSemanticOperationVersion(value.invocation.operationVersion),
            arguments: try value.invocation.arguments.sorted(by: { $0.key < $1.key }).map {
                ArgumentEntry(name: $0.key.rawValue, value: try AgentSemanticDirectArgument($0.value))
            },
            requestedOutputs: value.requestedOutputs.map(\.rawValue)
        )
    }

    public func semanticValue() throws -> SemanticDirectRequest {
        var mappedArguments: [SemanticArgumentID: SemanticArgument] = [:]
        mappedArguments.reserveCapacity(arguments.count)
        for entry in arguments {
            let id = SemanticArgumentID(entry.name)
            guard mappedArguments.updateValue(entry.value.semanticValue, forKey: id) == nil else {
                throw AgentSemanticRequestError(code: .duplicateArgument, name: entry.name)
            }
        }
        return SemanticDirectRequest(
            schemaVersion: schemaVersion.semanticValue,
            invocation: SemanticOperationInvocation(
                operationID: operationID,
                operationVersion: operationVersion.semanticValue,
                arguments: mappedArguments
            ),
            requestedOutputs: requestedOutputs.map(SemanticOutputID.init)
        )
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["schemaVersion", "operationID", "operationVersion", "arguments", "requestedOutputs"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(AgentSemanticSchemaVersion.self, forKey: .schemaVersion),
            operationID: try container.decode(DomainCapabilityID.self, forKey: .operationID),
            operationVersion: try container.decode(AgentSemanticOperationVersion.self, forKey: .operationVersion),
            arguments: try container.decode([ArgumentEntry].self, forKey: .arguments),
            requestedOutputs: try container.decode([String].self, forKey: .requestedOutputs)
        )
        _ = try semanticValue()
    }
}
