public struct AgentSemanticTelemetry: Codable, Equatable, Sendable {
    public struct Compilation: Codable, Equatable, Sendable {
        public let decodedValueCount: Int
        public let decodedNestingDepth: Int
        public let nodeCount: Int
        public let edgeCount: Int
        public let parameterCount: Int
        public let requestedOutputCount: Int
        public let localOutputReferenceCount: Int
        public let expressionCount: Int
        public let expressionDepth: Int
        public let expressionWork: UInt64
        public let loweredCommandCount: Int
        public let expandedSourceWork: UInt64

        private enum CodingKeys: String, CodingKey {
            case decodedValueCount
            case decodedNestingDepth
            case nodeCount
            case edgeCount
            case parameterCount
            case requestedOutputCount
            case localOutputReferenceCount
            case expressionCount
            case expressionDepth
            case expressionWork
            case loweredCommandCount
            case expandedSourceWork
        }

        public init(
            decodedValueCount: Int,
            decodedNestingDepth: Int,
            nodeCount: Int,
            edgeCount: Int,
            parameterCount: Int,
            requestedOutputCount: Int,
            localOutputReferenceCount: Int,
            expressionCount: Int,
            expressionDepth: Int,
            expressionWork: UInt64,
            loweredCommandCount: Int,
            expandedSourceWork: UInt64
        ) {
            self.decodedValueCount = decodedValueCount
            self.decodedNestingDepth = decodedNestingDepth
            self.nodeCount = nodeCount
            self.edgeCount = edgeCount
            self.parameterCount = parameterCount
            self.requestedOutputCount = requestedOutputCount
            self.localOutputReferenceCount = localOutputReferenceCount
            self.expressionCount = expressionCount
            self.expressionDepth = expressionDepth
            self.expressionWork = expressionWork
            self.loweredCommandCount = loweredCommandCount
            self.expandedSourceWork = expandedSourceWork
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [
                    "decodedValueCount", "decodedNestingDepth", "nodeCount", "edgeCount",
                    "parameterCount", "requestedOutputCount", "localOutputReferenceCount",
                    "expressionCount", "expressionDepth", "expressionWork",
                    "loweredCommandCount", "expandedSourceWork",
                ]
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                decodedValueCount: try container.decode(Int.self, forKey: .decodedValueCount),
                decodedNestingDepth: try container.decode(Int.self, forKey: .decodedNestingDepth),
                nodeCount: try container.decode(Int.self, forKey: .nodeCount),
                edgeCount: try container.decode(Int.self, forKey: .edgeCount),
                parameterCount: try container.decode(Int.self, forKey: .parameterCount),
                requestedOutputCount: try container.decode(Int.self, forKey: .requestedOutputCount),
                localOutputReferenceCount: try container.decode(Int.self, forKey: .localOutputReferenceCount),
                expressionCount: try container.decode(Int.self, forKey: .expressionCount),
                expressionDepth: try container.decode(Int.self, forKey: .expressionDepth),
                expressionWork: try container.decode(UInt64.self, forKey: .expressionWork),
                loweredCommandCount: try container.decode(Int.self, forKey: .loweredCommandCount),
                expandedSourceWork: try container.decode(UInt64.self, forKey: .expandedSourceWork)
            )
        }
    }

    public struct Execution: Codable, Equatable, Sendable {
        public let stepCount: Int
        public let commandCount: Int
        public let inputSlotCount: Int
        public let outputSlotCount: Int
        public let generatedIdentityCount: Int
        public let generatedSourceWork: UInt64

        private enum CodingKeys: String, CodingKey {
            case stepCount
            case commandCount
            case inputSlotCount
            case outputSlotCount
            case generatedIdentityCount
            case generatedSourceWork
        }

        public init(
            stepCount: Int,
            commandCount: Int,
            inputSlotCount: Int,
            outputSlotCount: Int,
            generatedIdentityCount: Int,
            generatedSourceWork: UInt64
        ) {
            self.stepCount = stepCount
            self.commandCount = commandCount
            self.inputSlotCount = inputSlotCount
            self.outputSlotCount = outputSlotCount
            self.generatedIdentityCount = generatedIdentityCount
            self.generatedSourceWork = generatedSourceWork
        }

        public init(from decoder: Decoder) throws {
            try AgentSemanticCoding.rejectUnknownKeys(
                from: decoder,
                allowedKeys: [
                    "stepCount", "commandCount", "inputSlotCount", "outputSlotCount",
                    "generatedIdentityCount", "generatedSourceWork",
                ]
            )
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                stepCount: try container.decode(Int.self, forKey: .stepCount),
                commandCount: try container.decode(Int.self, forKey: .commandCount),
                inputSlotCount: try container.decode(Int.self, forKey: .inputSlotCount),
                outputSlotCount: try container.decode(Int.self, forKey: .outputSlotCount),
                generatedIdentityCount: try container.decode(Int.self, forKey: .generatedIdentityCount),
                generatedSourceWork: try container.decode(UInt64.self, forKey: .generatedSourceWork)
            )
        }
    }

    public let compilation: Compilation
    public let execution: Execution

    private enum CodingKeys: String, CodingKey { case compilation, execution }

    public init(compilation: Compilation, execution: Execution) {
        self.compilation = compilation
        self.execution = execution
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["compilation", "execution"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            compilation: try container.decode(Compilation.self, forKey: .compilation),
            execution: try container.decode(Execution.self, forKey: .execution)
        )
    }
}
