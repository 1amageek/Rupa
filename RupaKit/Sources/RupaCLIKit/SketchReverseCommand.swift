import ArgumentParser
import RupaAutomation

public struct SketchReverseCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "reverse",
        abstract: "Reverse a supported source sketch curve."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .reverseSketchCurve(target: selection.decodedTarget())
        )
    }
}
