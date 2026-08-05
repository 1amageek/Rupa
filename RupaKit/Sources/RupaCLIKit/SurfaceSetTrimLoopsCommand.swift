import ArgumentParser
import Foundation
import RupaAgentRuntime
import RupaCore

public struct SurfaceSetTrimLoopsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-loops",
        abstract: "Set source-owned direct B-spline surface trim loops from UV p-curve JSON."
    )

    @Argument(help: "Path to the .swcad document for file or auto mode.")
    public var file: String?

    @Option(help: "SelectionReference JSON object for one direct B-spline surface reference.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(help: "SurfaceTrimLoop JSON object. Repeat for multiple loops.")
    public var trimLoop: [String] = []

    @Option(help: "JSON file containing one SurfaceTrimLoop object or an array.")
    public var trimLoopsFile: String?

    @Flag(help: "Clear authored trim loops and return to the full rectangular surface domain.")
    public var clear: Bool = false

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
        let surfaceReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let loops: [SurfaceTrimLoop] = try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: trimLoop,
            filePath: trimLoopsFile,
            clear: clear,
            valueName: "SurfaceTrimLoop",
            arrayName: "SurfaceTrimLoop"
        )

        try CLIExitCode.run {
            let writePolicy = try writeDestination.writePolicy(file: file, mode: mode, sessionID: id)
            let agentClient = CLIAgentClientFactory.makeAgentClient(
                mode: mode,
                sessionID: id,
                socket: agentSocket
            )
            let response = try CLIService().setSurfaceTrimLoops(
                target: CLIDocumentTarget(
                    fileURL: file.map(URL.init(fileURLWithPath:)),
                    sessionID: id
                ),
                reference: surfaceReference,
                trimLoops: loops,
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
