import ArgumentParser
import RupaCore
import SwiftCAD

public struct InspectSnapCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "snap",
        abstract: "Resolve grid, source, generated topology, measurement, and construction-plane snap candidates."
    )

    @OptionGroup
    public var document: CLIReadDocumentOptions

    @Option(help: "Input X coordinate.")
    public var x: Double

    @Option(help: "Input Y coordinate.")
    public var y: Double

    @Option(help: "Length unit for X and Y.")
    public var unit: LengthDisplayUnit = .meter

    @Option(help: "Optional SnapResolutionOptions JSON object.")
    public var options: String?

    @Option(help: "Optional JSON file containing one SnapResolutionOptions object.")
    public var optionsFile: String?

    public init() {}

    public func run() throws {
        let id = try document.resolvedSessionID()
        let snapOptions = try decodedOptions()
        let point = Point2D(
            x: unit.meters(from: x),
            y: unit.meters(from: y)
        )

        try CLIExitCode.run {
            let response = try CLIService().resolveSnap(
                target: document.target(sessionID: id),
                point: point,
                options: snapOptions,
                mode: document.mode,
                expectedGeneration: document.generation(),
                client: document.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }

    private func decodedOptions() throws -> SnapResolutionOptions {
        guard options != nil || optionsFile != nil else {
            return SnapResolutionOptions()
        }
        return try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: options,
            filePath: optionsFile,
            valueName: "SnapResolutionOptions"
        )
    }
}
