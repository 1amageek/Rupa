import ArgumentParser

public struct InspectSketchesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "sketches",
        abstract: "Return source sketch entities, regions, point handles, and SelectionTarget IDs."
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
                .sketchEntitySummary(
                    sessionID: sessionID,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.sketches(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
