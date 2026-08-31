import ArgumentParser
import RupaAutomation

public struct SketchUnjoinCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "unjoin",
        abstract: "Restore a supported joined source sketch curve."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .unjoinSketchCurve(target: selection.decodedTarget())
        )
    }
}
