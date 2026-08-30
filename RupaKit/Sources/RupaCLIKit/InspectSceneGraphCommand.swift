import ArgumentParser
import RupaCore

public struct InspectSceneGraphCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "scene-graph",
        abstract: "Return immutable Product scene-node placement and visibility from a live Rupa session."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    public init() {}

    public func run() throws {
        guard options.mode == .live else {
            throw EditorError(
                code: .commandInvalid,
                message: "Scene-graph inspection requires explicit live mode."
            )
        }
        guard let sessionID = try options.resolvedSessionID() else {
            throw EditorError(
                code: .commandInvalid,
                message: "Scene-graph inspection requires a live session ID."
            )
        }
        guard let client = options.agentClient(sessionID: sessionID) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Scene-graph inspection requires a live Agent client."
            )
        }

        try CLIExitCode.run {
            let response = try CLIService().sceneGraphSnapshotLiveSession(
                sessionID: sessionID,
                expectedGeneration: options.generation(),
                client: client
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
