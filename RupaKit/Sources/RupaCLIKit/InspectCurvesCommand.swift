import ArgumentParser

public struct InspectCurvesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "curves",
        abstract: "Return source curve samples, lengths, curvature, and continuity joins."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() throws {
        let id = try options.resolvedSessionID()

        try CLIExitCode.run {
            let response = try CLIService().curveAnalysis(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
