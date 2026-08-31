import ArgumentParser
import Foundation
import RupaCore

public struct InspectSurfaceBoundaryContinuityCompatibilityCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surface-boundary-continuity-compatibility",
        abstract: "Preflight whether two direct B-spline surface trim boundaries can be matched."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    @Option(help: "SelectionReference JSON object for the target surface trim.")
    public var target: String?

    @Option(help: "JSON file containing the target SelectionReference object.")
    public var targetFile: String?

    @Option(help: "SelectionReference JSON object for the reference surface trim.")
    public var reference: String?

    @Option(help: "JSON file containing the reference SelectionReference object.")
    public var referenceFile: String?

    public init() {}

    public func run() async throws {
        let id = try options.resolvedSessionID()
        let targetReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: target,
            filePath: targetFile,
            valueName: "Target SelectionReference"
        )
        let referenceReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "Reference SelectionReference"
        )

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation()
            ) { sessionID in
                .surfaceBoundaryContinuityCompatibility(
                    sessionID: sessionID,
                    target: targetReference,
                    reference: referenceReference,
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.surfaceBoundaryCompatibility(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
