import ArgumentParser

public struct InspectTopologyCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "topology",
        abstract: "Return generated body, face, edge, and vertex persistent names with SelectionTarget IDs."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try options.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: id),
                expectedGeneration: options.generation()
            ) { sessionID in
                .topologySummary(
                    sessionID: sessionID,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.topology(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
