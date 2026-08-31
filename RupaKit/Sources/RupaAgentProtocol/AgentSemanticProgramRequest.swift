import RupaCoreTypes
import RupaDomainFoundation

public struct AgentSemanticProgramRequest: Codable, Equatable, Sendable {
    public struct ParameterEntry: Codable, Equatable, Sendable {
        public let name: String
        public let value: AgentSemanticTypedValue

        private enum CodingKeys: String, CodingKey { case name, value }

        public init(name: String, value: AgentSemanticTypedValue) {
            self.name = name
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["name", "value"])
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                value: try container.decode(AgentSemanticTypedValue.self, forKey: .value)
            )
        }
    }

    public struct ArgumentEntry: Codable, Equatable, Sendable {
        public let name: String
        public let value: AgentSemanticProgramArgument

        private enum CodingKeys: String, CodingKey { case name, value }

        public init(name: String, value: AgentSemanticProgramArgument) {
            self.name = name
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["name", "value"])
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                name: try container.decode(String.self, forKey: .name),
                value: try container.decode(AgentSemanticProgramArgument.self, forKey: .value)
            )
        }
    }

    public struct Node: Codable, Equatable, Sendable {
        public let symbol: String
        public let operationID: DomainCapabilityID
        public let operationVersion: AgentSemanticOperationVersion
        public let arguments: [ArgumentEntry]

        private enum CodingKeys: String, CodingKey {
            case symbol
            case operationID
            case operationVersion
            case arguments
        }

        public init(
            symbol: String,
            operationID: DomainCapabilityID,
            operationVersion: AgentSemanticOperationVersion,
            arguments: [ArgumentEntry] = []
        ) {
            self.symbol = symbol
            self.operationID = operationID
            self.operationVersion = operationVersion
            self.arguments = arguments
        }

        init(_ value: SemanticProgramNode) {
            self.init(
                symbol: value.symbol.rawValue,
                operationID: value.invocation.operationID,
                operationVersion: AgentSemanticOperationVersion(value.invocation.operationVersion),
                arguments: value.invocation.arguments.sorted(by: { $0.key < $1.key }).map {
                    ArgumentEntry(name: $0.key.rawValue, value: AgentSemanticProgramArgument($0.value))
                }
            )
        }

        func semanticValue() throws -> SemanticProgramNode {
            var mappedArguments: [SemanticArgumentID: SemanticArgument] = [:]
            mappedArguments.reserveCapacity(arguments.count)
            for entry in arguments {
                let id = SemanticArgumentID(entry.name)
                guard mappedArguments.updateValue(entry.value.semanticValue, forKey: id) == nil else {
                    throw AgentSemanticRequestError(code: .duplicateArgument, name: entry.name)
                }
            }
            return SemanticProgramNode(
                symbol: ProgramNodeSymbol(symbol),
                invocation: SemanticOperationInvocation(
                    operationID: operationID,
                    operationVersion: operationVersion.semanticValue,
                    arguments: mappedArguments
                )
            )
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: ["symbol", "operationID", "operationVersion", "arguments"]
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                symbol: try container.decode(String.self, forKey: .symbol),
                operationID: try container.decode(DomainCapabilityID.self, forKey: .operationID),
                operationVersion: try container.decode(AgentSemanticOperationVersion.self, forKey: .operationVersion),
                arguments: try container.decode([ArgumentEntry].self, forKey: .arguments)
            )
        }
    }

    public let schemaVersion: AgentSemanticSchemaVersion
    public let parameters: [ParameterEntry]
    public let nodes: [Node]
    public let requestedOutputs: [AgentSemanticOutputReference]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case parameters
        case nodes
        case requestedOutputs
    }

    public init(
        schemaVersion: AgentSemanticSchemaVersion,
        parameters: [ParameterEntry] = [],
        nodes: [Node],
        requestedOutputs: [AgentSemanticOutputReference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.parameters = parameters
        self.nodes = nodes
        self.requestedOutputs = requestedOutputs
    }

    public init(_ value: SemanticProgram) {
        self.init(
            schemaVersion: AgentSemanticSchemaVersion(value.schemaVersion),
            parameters: value.parameters.sorted(by: { $0.key < $1.key }).map {
                ParameterEntry(name: $0.key.rawValue, value: AgentSemanticTypedValue($0.value))
            },
            nodes: value.nodes.map(Node.init),
            requestedOutputs: value.requestedOutputs.map(AgentSemanticOutputReference.init)
        )
    }

    public func semanticValue() throws -> SemanticProgram {
        var mappedParameters: [ProgramParameterID: SemanticTypedValue] = [:]
        mappedParameters.reserveCapacity(parameters.count)
        for entry in parameters {
            let id = ProgramParameterID(entry.name)
            guard mappedParameters.updateValue(entry.value.semanticValue, forKey: id) == nil else {
                throw AgentSemanticRequestError(code: .duplicateParameter, name: entry.name)
            }
        }
        return SemanticProgram(
            schemaVersion: schemaVersion.semanticValue,
            parameters: mappedParameters,
            nodes: try nodes.map { try $0.semanticValue() },
            requestedOutputs: requestedOutputs.map(\.semanticValue)
        )
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["schemaVersion", "parameters", "nodes", "requestedOutputs"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(AgentSemanticSchemaVersion.self, forKey: .schemaVersion),
            parameters: try container.decode([ParameterEntry].self, forKey: .parameters),
            nodes: try container.decode([Node].self, forKey: .nodes),
            requestedOutputs: try container.decode([AgentSemanticOutputReference].self, forKey: .requestedOutputs)
        )
        _ = try semanticValue()
    }
}
