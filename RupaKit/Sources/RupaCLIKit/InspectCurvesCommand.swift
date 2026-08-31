import ArgumentParser

public struct InspectCurvesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "curves",
        abstract: "Return source curve samples, lengths, curvature, and continuity joins."
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
                .curveAnalysis(
                    sessionID: sessionID,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.curves(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
