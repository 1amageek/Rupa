import ArgumentParser
import Foundation
import RupaCore

public struct InspectSurfaceBoundaryContinuityCompatibilityCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surface-boundary-continuity-compatibility",
        abstract: "Preflight whether two direct B-spline surface trim boundaries can be matched."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(help: "SelectionReference JSON object for the target surface trim.")
    public var target: String?

    @Option(help: "JSON file containing the target SelectionReference object.")
    public var targetFile: String?

    @Option(help: "SelectionReference JSON object for the reference surface trim.")
    public var reference: String?

    @Option(help: "JSON file containing the reference SelectionReference object.")
    public var referenceFile: String?

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try CLISelectionInputParser.optionalSessionID(sessionID)
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

        try CLIExitCode.run {
            let response = try CLIService().surfaceBoundaryContinuityCompatibility(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                targetReference: targetReference,
                reference: referenceReference,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                client: CLIAgentClientFactory.makeAgentClient(
                    mode: mode,
                    sessionID: id,
                    socket: agentSocket
                )
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}
