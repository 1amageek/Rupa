import ArgumentParser

public struct InspectSurfaceContinuityCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surface-continuity",
        abstract: "Return generated B-spline surface adjacency and continuity diagnostics."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() throws {
        let id = try options.resolvedSessionID()

        try CLIExitCode.run {
            let response = try CLIService().surfaceContinuitySummary(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
