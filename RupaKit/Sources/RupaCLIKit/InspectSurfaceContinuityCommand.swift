import ArgumentParser

public struct InspectSurfaceContinuityCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surface-continuity",
        abstract: "Return generated B-spline surface adjacency and continuity diagnostics."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let id = try options.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation()
            ) { sessionID in
                .surfaceContinuitySummary(
                    sessionID: sessionID,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.surfaceContinuity(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
