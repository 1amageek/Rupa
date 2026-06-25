import ArgumentParser

public struct InspectConstructionPlanesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "construction-planes",
        abstract: "Return saved construction planes and the active construction-plane state."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() throws {
        let id = try options.resolvedSessionID()

        try CLIExitCode.run {
            let response = try CLIService().constructionPlaneSummary(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
