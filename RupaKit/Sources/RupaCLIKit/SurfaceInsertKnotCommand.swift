import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceInsertKnotCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "insert-knot",
        abstract: "Insert or duplicate an editable source-owned B-spline surface knot."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(help: "SelectionReference JSON object for one surface span or knot.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(help: "Inserted knot scalar value.")
    public var value: Double

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
        let insertionReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let valueExpression = try CLIExpressionParser.scalar(
            value: value,
            valueName: "Surface knot insertion value"
        )

        try CLIExitCode.run {
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().insertSurfaceKnot(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                reference: insertionReference,
                value: valueExpression,
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
