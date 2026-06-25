import ArgumentParser
import RupaAutomation

public struct SketchReverseCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "reverse",
        abstract: "Reverse a supported source sketch curve."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISketchEditTargetOptions

    public init() {}

    public func run() throws {
        try CLISketchEditCommandRunner.run(
            document: document,
            command: .reverseSketchCurve(target: selection.decodedTarget())
        )
    }
}
