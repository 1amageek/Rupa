import ArgumentParser
import RupaCore

public struct InspectSurfaceFramesCommand: AsyncParsableCommand {
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

    public func run() async throws {
        let id = try options.resolvedSessionID()
        let queries: [SurfaceFrameQuery] = try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: queryPayloads,
            filePath: queriesFile,
            clear: false,
            valueName: "SurfaceFrameQuery",
            arrayName: "SurfaceFrameQuery"
        )

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation()
            ) { sessionID in
                .surfaceFrames(
                    sessionID: sessionID,
                    queries: queries,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.surfaceFrames(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
