import ArgumentParser
import RupaAutomation

public struct SketchConvertLineToSplineCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "convert-line-to-spline",
        abstract: "Convert a supported source sketch line into a cubic spline."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .convertSketchLineToSpline(target: selection.decodedTarget())
        )
    }
}
