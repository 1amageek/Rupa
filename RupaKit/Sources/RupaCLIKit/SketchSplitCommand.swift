import ArgumentParser
import RupaAutomation

public struct SketchSplitCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "split",
        abstract: "Split a supported source sketch curve at a scalar fraction."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Split fraction along the selected curve.")
    public var fraction: Double

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .splitSketchCurve(
                target: selection.decodedTarget(),
                fraction: try CLIExpressionParser.scalar(value: fraction, valueName: "Split fraction")
            )
        )
    }
}
