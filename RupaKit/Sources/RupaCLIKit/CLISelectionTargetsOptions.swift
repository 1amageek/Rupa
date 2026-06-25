import ArgumentParser
import RupaCore

public struct CLISelectionTargetsOptions: ParsableArguments {
    @Option(
        name: .customLong("target"),
        help: "SelectionTarget JSON object. Repeat to pass multiple targets."
    )
    public var targetPayloads: [String] = []

    @Option(help: "JSON file containing one SelectionTarget object or an array of SelectionTarget objects.")
    public var targetsFile: String?

    public init() {}

    public func decodedTargets() throws -> [SelectionTarget] {
        try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: targetPayloads,
            filePath: targetsFile,
            clear: false,
            valueName: "SelectionTarget",
            arrayName: "SelectionTarget"
        )
    }
}
