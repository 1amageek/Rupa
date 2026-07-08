import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceMoveTrimControlPointCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "move-trim-control-point",
        abstract: "Move a source-owned authored direct B-spline surface trim p-curve interior control point."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(help: "SelectionReference JSON object for one authored surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Strict interior p-curve control point index.")
    public var controlPointIndex: Int

    @Option(parsing: .unconditional, help: "Target U parameter.")
    public var u: Double

    @Option(parsing: .unconditional, help: "Target V parameter.")
    public var v: Double

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

    @OptionGroup
    public var writeDestination: CLIWriteDestinationOptions

    public init() {}

    public func run() throws {
        let id = try CLISelectionInputParser.optionalSessionID(sessionID)
        let trimReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let uExpression = try CLIExpressionParser.scalar(
            value: u,
            valueName: "Surface trim control point U parameter"
        )
        let vExpression = try CLIExpressionParser.scalar(
            value: v,
            valueName: "Surface trim control point V parameter"
        )

        try CLIExitCode.run {
            let writePolicy = try writeDestination.writePolicy(file: file, mode: mode, sessionID: id)
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().moveSurfaceTrimControlPoint(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                reference: trimReference,
                controlPointIndex: controlPointIndex,
                u: uExpression,
                v: vExpression,
                mode: mode,
                expectedGeneration: expectedGeneration.map(DocumentGeneration.init),
                dryRun: dryRun,
                writePolicy: writePolicy,
                forceFileEdit: forceFileEdit,
                client: agentClient
            )
            try CLIOutput.write(response: response, asJSON: json)
        }
    }
}
