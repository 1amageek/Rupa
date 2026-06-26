import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchJoinCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "join",
        abstract: "Join two supported source sketch curves."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Adjacent SelectionTarget JSON object.")
    public var adjacentTarget: String?

    @Option(help: "JSON file containing one adjacent SelectionTarget object.")
    public var adjacentTargetFile: String?

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .joinSketchCurves(
                target: selection.decodedTarget(),
                adjacentTarget: try decodedAdjacentTarget()
            )
        )
    }

    private func decodedAdjacentTarget() throws -> SelectionTarget {
        try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: adjacentTarget,
            filePath: adjacentTargetFile,
            valueName: "Adjacent SelectionTarget"
        )
    }
}
