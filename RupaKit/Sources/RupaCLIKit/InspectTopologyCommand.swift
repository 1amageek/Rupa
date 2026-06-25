import ArgumentParser

public struct InspectTopologyCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "topology",
        abstract: "Return generated body, face, edge, and vertex persistent names with SelectionTarget IDs."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() throws {
        let id = try options.resolvedSessionID()

        try CLIExitCode.run {
            let response = try CLIService().topologySummary(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
