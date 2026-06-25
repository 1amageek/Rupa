import ArgumentParser

public struct InspectSketchesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sketches",
        abstract: "Return source sketch entities, regions, point handles, and SelectionTarget IDs."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() throws {
        let id = try options.resolvedSessionID()

        try CLIExitCode.run {
            let response = try CLIService().sketchEntitySummary(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
