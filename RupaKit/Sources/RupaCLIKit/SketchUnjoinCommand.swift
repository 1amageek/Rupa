import ArgumentParser
import RupaAutomation

public struct SketchUnjoinCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "unjoin",
        abstract: "Restore a supported joined source sketch curve."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .unjoinSketchCurve(target: selection.decodedTarget())
        )
    }
}
