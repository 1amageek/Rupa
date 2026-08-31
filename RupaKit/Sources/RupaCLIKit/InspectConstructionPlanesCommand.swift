import ArgumentParser

public struct InspectConstructionPlanesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "construction-planes",
        abstract: "Return saved construction planes and the active construction-plane state."
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
                .constructionPlaneSummary(
                    sessionID: sessionID,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.constructionPlanes(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
