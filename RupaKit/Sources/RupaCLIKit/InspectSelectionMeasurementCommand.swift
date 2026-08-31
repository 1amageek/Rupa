import ArgumentParser
import RupaCore

public struct InspectSelectionMeasurementCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "selection-measurement",
        abstract: "Return a point, distance, or angle measurement for typed SelectionReference values."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    @Option(help: "CADAgentMeasurementQuery JSON object.")
    public var query: String?

    @Option(help: "JSON file containing one CADAgentMeasurementQuery object.")
    public var queryFile: String?

    public init() {}

    public func run() async throws {
        let id = try options.resolvedSessionID()
        let measurementQuery: CADAgentMeasurementQuery = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: query,
            filePath: queryFile,
            valueName: "CADAgentMeasurementQuery"
        )

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation()
            ) { sessionID in
                .selectionMeasurement(
                    sessionID: sessionID,
                    query: measurementQuery,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.selectionMeasurement(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
