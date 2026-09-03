import Foundation
import MCP
import RupaAgentProtocol
import RupaCoreTypes

public struct RupaMCPServer: Sendable {
    private static let maximumCapabilityPageSize = 50

    private let access: any RupaMCPAccess
    private let maximumByteCount: Int

    public init(
        access: any RupaMCPAccess,
        maximumByteCount: Int = AgentProtocolEncodingLimits.defaultMaximumByteCount
    ) {
        precondition(maximumByteCount > 0, "maximumByteCount must be positive")
        self.access = access
        self.maximumByteCount = maximumByteCount
    }

    public func run(transport: any Transport = StdioTransport()) async throws {
        let server = try await start(transport: transport)
        await server.waitUntilCompleted()
        await server.stop()
    }

    func start(transport: any Transport) async throws -> Server {
        let server = Server(
            name: "rupa",
            version: "1.0.0",
            instructions: "Discover capabilities before constructing semantic requests. Mutations remain in memory until rupa_save succeeds.",
            capabilities: .init(tools: .init(listChanged: false)),
            configuration: .strict
        )
        await server.withMethodHandler(ListTools.self) { _ -> ListTools.Result in
            ListTools.Result(tools: Self.tools)
        }
        await server.withMethodHandler(CallTool.self) { parameters -> CallTool.Result in
            await dispatch(parameters)
        }
        await server.withMethodHandler(CallTool.self) { parameters -> Server.ModernHandlerResult<CallTool.Result> in
            .complete(await dispatch(parameters))
        }
        try await server.start(transport: transport)
        return server
    }

    private func dispatch(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        do {
            let arguments = parameters.arguments ?? [:]
            switch parameters.name {
            case "rupa_agent_status":
                try validate(arguments, allowedKeys: [])
                return try result(await access.status())
            case "rupa_list_sessions":
                try validate(arguments, allowedKeys: [])
                return try result(SessionList(sessions: await access.sessions()))
            case "rupa_list_capabilities":
                try validate(arguments, allowedKeys: ["cursor", "limit"])
                return try result(try await capabilityPage(arguments))
            case "rupa_invoke_capability":
                try validate(
                    arguments,
                    allowedKeys: ["projectPath", "sessionID", "request", "dryRun"]
                )
                let request: AgentSemanticDirectRequest = try decode(required("request", in: arguments))
                return try semanticResult(
                    await access.invokeCapability(
                        target: try target(arguments),
                        request: request,
                        dryRun: try bool("dryRun", in: arguments, default: false)
                    )
                )
            case "rupa_execute_program":
                try validate(
                    arguments,
                    allowedKeys: ["projectPath", "sessionID", "program", "dryRun"]
                )
                let program: AgentSemanticProgramRequest = try decode(required("program", in: arguments))
                return try semanticResult(
                    await access.executeProgram(
                        target: try target(arguments),
                        program: program,
                        dryRun: try bool("dryRun", in: arguments, default: false)
                    )
                )
            case "rupa_save":
                try validate(
                    arguments,
                    allowedKeys: ["projectPath", "sessionID", "expectedGeneration"]
                )
                return try result(
                    await access.save(
                        target: try target(arguments),
                        expectedGeneration: try generation(arguments["expectedGeneration"])
                    )
                )
            default:
                throw RupaMCPError.invalidArguments("Unknown Rupa MCP tool: \(parameters.name).")
            }
        } catch {
            return failure(error)
        }
    }

    private func capabilityPage(_ arguments: [String: Value]) async throws -> CapabilityPage {
        let limit = try integer("limit", in: arguments, default: 20)
        guard (1...Self.maximumCapabilityPageSize).contains(limit) else {
            throw RupaMCPError.invalidArguments(
                "limit must be between 1 and \(Self.maximumCapabilityPageSize)."
            )
        }
        let offset: Int
        if let cursor = arguments["cursor"] {
            guard let value = cursor.stringValue, let parsed = Int(value), parsed >= 0 else {
                throw RupaMCPError.invalidArguments("cursor must be a nonnegative decimal string.")
            }
            offset = parsed
        } else {
            offset = 0
        }
        let capabilities = try await access.capabilities()
        guard offset <= capabilities.count else {
            throw RupaMCPError.invalidArguments("cursor is outside the capability catalog.")
        }
        let end = min(capabilities.count, offset + limit)
        return CapabilityPage(
            capabilities: Array(capabilities[offset..<end]),
            nextCursor: end < capabilities.count ? String(end) : nil
        )
    }

    private func target(_ arguments: [String: Value]) throws -> RupaMCPProjectTarget {
        let pathValue = arguments["projectPath"]
        let sessionValue = arguments["sessionID"]
        guard (pathValue == nil) != (sessionValue == nil) else {
            throw RupaMCPError.invalidArguments(
                "Provide exactly one of projectPath or sessionID."
            )
        }
        if let pathValue {
            guard let path = pathValue.stringValue,
                  !path.isEmpty,
                  (path as NSString).isAbsolutePath else {
                throw RupaMCPError.invalidArguments("projectPath must be a nonempty absolute path.")
            }
            return .project(URL(fileURLWithPath: path))
        }
        guard let value = sessionValue?.stringValue, let id = UUID(uuidString: value) else {
            throw RupaMCPError.invalidArguments("sessionID must be a UUID string.")
        }
        return .session(id)
    }

    private func validate(_ arguments: [String: Value], allowedKeys: Set<String>) throws {
        let unknownKeys = Set(arguments.keys).subtracting(allowedKeys)
        guard unknownKeys.isEmpty else {
            throw RupaMCPError.invalidArguments(
                "Unknown argument fields: \(unknownKeys.sorted().joined(separator: ", "))."
            )
        }
        let byteCount = try JSONEncoder().encode(Value.object(arguments)).count
        guard byteCount <= maximumByteCount else {
            throw RupaMCPError.requestTooLarge(actual: byteCount, maximum: maximumByteCount)
        }
    }

    private func required(_ name: String, in arguments: [String: Value]) throws -> Value {
        guard let value = arguments[name] else {
            throw RupaMCPError.invalidArguments("\(name) is required.")
        }
        return value
    }

    private func bool(
        _ name: String,
        in arguments: [String: Value],
        default defaultValue: Bool
    ) throws -> Bool {
        guard let value = arguments[name] else {
            return defaultValue
        }
        guard let result = value.boolValue else {
            throw RupaMCPError.invalidArguments("\(name) must be a boolean.")
        }
        return result
    }

    private func integer(
        _ name: String,
        in arguments: [String: Value],
        default defaultValue: Int
    ) throws -> Int {
        guard let value = arguments[name] else {
            return defaultValue
        }
        guard let result = value.intValue else {
            throw RupaMCPError.invalidArguments("\(name) must be an integer.")
        }
        return result
    }

    private func generation(_ value: Value?) throws -> DocumentGeneration? {
        guard let value else {
            return nil
        }
        guard let integer = value.intValue, integer >= 0 else {
            throw RupaMCPError.invalidArguments("expectedGeneration must be a nonnegative integer.")
        }
        return DocumentGeneration(UInt64(integer))
    }

    private func decode<Decoded: Decodable>(_ value: Value) throws -> Decoded {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumByteCount else {
            throw RupaMCPError.requestTooLarge(actual: data.count, maximum: maximumByteCount)
        }
        do {
            return try JSONDecoder().decode(Decoded.self, from: data)
        } catch {
            throw RupaMCPError.invalidArguments(
                "The structured value does not match \(Decoded.self): \(error)"
            )
        }
    }

    private func result<Output: Encodable>(
        _ output: Output,
        isError: Bool = false
    ) throws -> CallTool.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(output)
        guard data.count <= maximumByteCount else {
            throw RupaMCPError.responseTooLarge(actual: data.count, maximum: maximumByteCount)
        }
        let structuredContent = try JSONDecoder().decode(Value.self, from: data)
        return CallTool.Result(
            content: [
                .text(
                    text: String(decoding: data, as: UTF8.self),
                    annotations: nil,
                    _meta: nil
                ),
            ],
            structuredContent: Optional.some(structuredContent),
            isError: isError
        )
    }

    private func semanticResult(_ output: AgentSemanticExecutionResult) throws -> CallTool.Result {
        switch output {
        case .success:
            try result(output)
        case .prepublicationFailure, .committedFailure:
            try result(output, isError: true)
        }
    }

    private func failure(_ error: any Error) -> CallTool.Result {
        let code = (error as? RupaMCPError)?.code ?? "rupaOperationFailed"
        let value: Value = .object([
            "error": .object([
                "code": .string(code),
                "message": .string(error.localizedDescription),
            ]),
        ])
        return CallTool.Result(
            content: [
                .text(text: error.localizedDescription, annotations: nil, _meta: nil),
            ],
            structuredContent: Optional.some(value),
            isError: true
        )
    }
}

private struct SessionList: Encodable {
    let sessions: [WorkspaceSessionSummary]
}

private struct CapabilityPage: Encodable {
    let capabilities: [AgentCapabilityDescriptor]
    let nextCursor: String?
}

private extension RupaMCPServer {
    static let tools: [Tool] = [
        Tool(
            name: "rupa_agent_status",
            title: "Rupa Agent Status",
            description: "Report whether the Rupa Agent is running and how many projects are open.",
            inputSchema: emptyInputSchema,
            annotations: readAnnotations,
            outputSchema: objectOutputSchema
        ),
        Tool(
            name: "rupa_list_sessions",
            title: "List Rupa Sessions",
            description: "List open Rupa project sessions and their current authority coordinates.",
            inputSchema: emptyInputSchema,
            annotations: readAnnotations,
            outputSchema: objectOutputSchema
        ),
        Tool(
            name: "rupa_list_capabilities",
            title: "List Rupa Capabilities",
            description: "Read one bounded page of typed Rupa CAD capability descriptors.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "cursor": .object(["type": "string"]),
                    "limit": .object(["type": "integer", "minimum": 1, "maximum": 50]),
                ]),
                "additionalProperties": false,
            ]),
            annotations: readAnnotations,
            outputSchema: objectOutputSchema
        ),
        Tool(
            name: "rupa_invoke_capability",
            title: "Invoke Rupa Capability",
            description: "Execute one typed semantic CAD operation in an open Rupa project without saving it.",
            inputSchema: targetInputSchema(
                valueName: "request",
                valueDescription: "A canonical AgentSemanticDirectRequest object with schemaVersion, operationID, operationVersion, arguments, and requestedOutputs.",
                includesDryRun: true
            ),
            annotations: mutationAnnotations,
            outputSchema: objectOutputSchema
        ),
        Tool(
            name: "rupa_execute_program",
            title: "Execute Rupa Program",
            description: "Execute one bounded atomic semantic CAD program in an open Rupa project without saving it.",
            inputSchema: targetInputSchema(
                valueName: "program",
                valueDescription: "A canonical AgentSemanticProgramRequest object with schemaVersion, parameters, nodes, and requestedOutputs.",
                includesDryRun: true
            ),
            annotations: mutationAnnotations,
            outputSchema: objectOutputSchema
        ),
        Tool(
            name: "rupa_save",
            title: "Save Rupa Project",
            description: "Explicitly save the current in-memory Rupa project generation.",
            inputSchema: targetInputSchema(
                valueName: "expectedGeneration",
                valueDescription: "The optional nonnegative document generation that must still be current.",
                valueSchema: .object(["type": "integer", "minimum": 0]),
                valueRequired: false,
                includesDryRun: false
            ),
            annotations: mutationAnnotations,
            outputSchema: objectOutputSchema
        ),
    ]

    static let emptyInputSchema: Value = .object([
        "type": "object",
        "properties": .object([:]),
        "additionalProperties": false,
    ])

    static let objectOutputSchema: Value = .object(["type": "object"])

    static let readAnnotations = Tool.Annotations(
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
    )

    static let mutationAnnotations = Tool.Annotations(
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: false
    )

    static func targetInputSchema(
        valueName: String,
        valueDescription: String,
        valueSchema: Value = .object(["type": "object"]),
        valueRequired: Bool = true,
        includesDryRun: Bool
    ) -> Value {
        var properties: [String: Value] = [
            "projectPath": .object([
                "type": "string",
                "minLength": 1,
                "description": "Absolute path to a .rupa project opened by Rupa.",
            ]),
            "sessionID": .object([
                "type": "string",
                "format": "uuid",
                "description": "Identifier of an already open Rupa project session.",
            ]),
            valueName: mergedSchema(valueSchema, description: valueDescription),
        ]
        if includesDryRun {
            properties["dryRun"] = .object([
                "type": "boolean",
                "default": false,
                "description": "Validate and evaluate without publishing a project mutation.",
            ])
        }
        let required = valueRequired ? [Value.string(valueName)] : []
        return .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array(required),
            "oneOf": .array([
                .object(["required": .array(["projectPath"])]),
                .object(["required": .array(["sessionID"])]),
            ]),
            "additionalProperties": false,
        ])
    }

    static func mergedSchema(_ schema: Value, description: String) -> Value {
        guard case .object(var fields) = schema else {
            return schema
        }
        fields["description"] = .string(description)
        return .object(fields)
    }
}
