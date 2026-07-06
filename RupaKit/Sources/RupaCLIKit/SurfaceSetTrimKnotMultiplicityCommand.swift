import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceSetTrimKnotMultiplicityCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-knot-multiplicity",
        abstract: "Set an editable source-owned B-spline surface trim p-curve knot multiplicity."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(help: "SelectionReference JSON object for one authored B-spline surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "B-spline trim p-curve knot index from surfaceSourceSummary.")
    public var knotIndex: Int

    @Option(parsing: .unconditional, help: "Positive target multiplicity.")
    public var multiplicity: Int

    @Option(help: "Edit mode: auto, file, or live.")
    public var mode: CLIEditMode = .auto

    @Option(help: "Open document session UUID for live mode.")
    public var sessionID: String?

    @Option(help: "Expected document generation for live mode.")
    public var expectedGeneration: UInt64?

    @Flag(help: "Validate the command without saving the changed file.")
    public var dryRun: Bool = false

    @Flag(help: "Allow direct file mutation even if the app reports the same file as open.")
    public var forceFileEdit: Bool = false

    @Option(help: "Optional Rupa agent socket used to detect open document conflicts.")
    public var agentSocket: String?

    @Flag(help: "Print a JSON result.")
    public var json: Bool = false

    public init() {}

    public func run() throws {
        let id = try CLISelectionInputParser.optionalSessionID(sessionID)
        let trimReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )

        try CLIExitCode.run {
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().setSurfaceTrimKnotMultiplicity(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                reference: trimReference,
                knotIndex: knotIndex,
                multiplicity: multiplicity,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}
