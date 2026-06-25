import ArgumentParser
import RupaCore

public struct CLISketchEditTargetOptions: ParsableArguments {
    @Option(help: "SelectionTarget JSON object.")
    public var target: String?

    @Option(help: "JSON file containing one SelectionTarget object.")
    public var targetFile: String?

    public init() {}

    public func decodedTarget() throws -> SelectionTarget {
        try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: target,
            filePath: targetFile,
            valueName: "SelectionTarget"
        )
    }
}
