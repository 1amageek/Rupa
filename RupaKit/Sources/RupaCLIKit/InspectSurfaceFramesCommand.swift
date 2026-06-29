import ArgumentParser
import RupaCore

public struct InspectSurfaceFramesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surface-frames",
        abstract: "Return UVN local frames for generated B-spline surface face parameters and surface selection references."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    @Option(
        name: .customLong("query"),
        help: "SurfaceFrameQuery JSON object. Repeat for multiple UVN frame queries."
    )
    public var queryPayloads: [String] = []

    @Option(help: "JSON file containing one SurfaceFrameQuery object or an array.")
    public var queriesFile: String?

    public init() {}

    public func run() throws {
        let id = try options.resolvedSessionID()
        let queries: [SurfaceFrameQuery] = try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: queryPayloads,
            filePath: queriesFile,
            clear: false,
            valueName: "SurfaceFrameQuery",
            arrayName: "SurfaceFrameQuery"
        )

        try CLIExitCode.run {
            let response = try CLIService().surfaceFrames(
                target: options.target(sessionID: id),
                queries: queries,
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
