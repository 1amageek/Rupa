import ArgumentParser

public struct InspectSceneGraphCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "scene-graph",
        abstract: "Return immutable Product scene-node placement and visibility from a live Rupa session."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        let sessionID = try options.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: sessionID),
                expectedGeneration: options.generation()
            ) { resolvedSessionID in
                .sceneGraphSnapshot(
                    sessionID: resolvedSessionID,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.sceneGraph(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
