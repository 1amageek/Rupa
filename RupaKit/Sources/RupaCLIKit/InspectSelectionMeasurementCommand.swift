import ArgumentParser
import RupaCore

public struct InspectSelectionMeasurementCommand: ParsableCommand {
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

    public func run() throws {
        let id = try options.resolvedSessionID()
        let measurementQuery: CADAgentMeasurementQuery = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: query,
            filePath: queryFile,
            valueName: "CADAgentMeasurementQuery"
        )

        try CLIExitCode.run {
            let response = try CLIService().selectionMeasurement(
                target: options.target(sessionID: id),
                query: measurementQuery,
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
