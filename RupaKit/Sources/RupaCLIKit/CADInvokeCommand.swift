import ArgumentParser
import Foundation
import RupaAgentProtocol

/// Invokes one versioned semantic CAD operation.
public struct CADInvokeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "invoke",
        abstract: "Invoke one qualified, versioned CAD operation."
    )

    @Argument(
        help: "Project path followed by operation ID, or operation ID with --session-id."
    )
    public var positional: [String] = []

    @OptionGroup
    public var access: CADSemanticAccessOptions

    @Option(name: .customLong("schema-version"), help: "Semantic schema version (major.minor.patch).")
    public var schemaVersion: String

    @Option(name: .customLong("version"), help: "Operation version (major.minor.patch).")
    public var operationVersion: String

    @Option(
        name: .customLong("argument"),
        help: "One JSON encoded typed argument entry; repeat for multiple arguments."
    )
    public var argumentPayloads: [String] = []

    @Option(
        name: .customLong("arguments-file"),
        help: "JSON file or bounded JSON value containing typed argument entries."
    )
    public var argumentsFile: String?

    @Option(name: .customLong("output"), help: "Requested output ID; repeat to request multiple outputs.")
    public var requestedOutputs: [String] = []

    public init() {}

    public func run() async throws {
        try await CLIExitCode.run {
            let invocation = try buildInvocation()
            let result = try await CLIService().invokeCapability(
                target: invocation.target,
                request: invocation.request,
                dryRun: access.dryRun
            )
            try CLIOutput.write(response: result, asJSON: access.json)
        }
    }

    private func buildInvocation() throws -> (
        target: CLIDocumentTarget,
        request: AgentSemanticDirectRequest
    ) {
        let operationRawValue: String
        let file: String?
        switch (access.sessionID != nil, positional.count) {
        case (true, 1):
            file = nil
            operationRawValue = positional[0]
        case (false, 2):
            file = positional[0]
            operationRawValue = positional[1]
        default:
            throw CADSemanticInputError.invalidInvocationShape(
                "Provide a project path and operation ID, or one operation ID with --session-id."
            )
        }

        let target = try access.target(file: file)
        let operationID = try CADSemanticInputReader.operationID(operationRawValue)
        let schema = try CADSemanticInputReader.parseVersion(
            schemaVersion,
            label: "Schema version"
        )
        let version = try CADSemanticInputReader.parseVersion(
            operationVersion,
            label: "Operation version"
        )
        let arguments = try decodeArguments()
        return (
            target,
            AgentSemanticDirectRequest(
                schemaVersion: AgentSemanticSchemaVersion(
                    major: schema.major,
                    minor: schema.minor,
                    patch: schema.patch
                ),
                operationID: operationID,
                operationVersion: AgentSemanticOperationVersion(
                    major: version.major,
                    minor: version.minor,
                    patch: version.patch
                ),
                arguments: arguments,
                requestedOutputs: requestedOutputs
            )
        )
    }

    private func decodeArguments() throws -> [AgentSemanticDirectRequest.ArgumentEntry] {
        guard argumentsFile == nil || argumentPayloads.isEmpty else {
            throw CADSemanticInputError.conflictingArgumentSources
        }
        if let argumentsFile {
            let arguments: [AgentSemanticDirectRequest.ArgumentEntry] = try CADSemanticInputReader.decode(
                [AgentSemanticDirectRequest.ArgumentEntry].self,
                source: argumentsFile,
                label: "CAD arguments"
            )
            try validateUniqueArgumentNames(arguments)
            return arguments
        }
        let arguments = try argumentPayloads.map { payload in
            try CADSemanticInputReader.decode(
                AgentSemanticDirectRequest.ArgumentEntry.self,
                source: payload,
                label: "CAD argument"
            )
        }
        try validateUniqueArgumentNames(arguments)
        return arguments
    }

    private func validateUniqueArgumentNames(
        _ arguments: [AgentSemanticDirectRequest.ArgumentEntry]
    ) throws {
        var names = Set<String>()
        for argument in arguments {
            guard names.insert(argument.name).inserted else {
                throw CADSemanticInputError.duplicateArgument(argument.name)
            }
        }
    }
}
