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

    @Option(help: "Join continuity: g0, g1, or g2. G2 is reserved and rejected until the source continuity solver exists.")
    public var continuity: String = SketchCurveJoinContinuity.g0.rawValue

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .joinSketchCurves(
                target: selection.decodedTarget(),
                adjacentTarget: try decodedAdjacentTarget(),
                continuity: try decodedContinuity()
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

    private func decodedContinuity() throws -> SketchCurveJoinContinuity {
        guard let decoded = SketchCurveJoinContinuity(rawValue: continuity.lowercased()) else {
            throw ValidationError("Join continuity must be one of: g0, g1, g2.")
        }
        return decoded
    }
}
