import ArgumentParser
import RupaCore

public struct InspectViewportCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "viewport",
        abstract: "Return the exact immutable visible-item projection from a live Rupa session."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() async throws {
        guard options.mode == .live else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport inspection requires explicit live mode."
            )
        }
        let sessionID = try options.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: sessionID),
                mode: .live,
                expectedGeneration: options.generation()
            ) { resolvedSessionID in
                .viewportSnapshot(
                    sessionID: resolvedSessionID,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.viewport(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
