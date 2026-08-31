import ArgumentParser
import RupaAutomation

public struct SketchTrimCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "trim",
        abstract: "Trim a supported source sketch curve segment."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .trimSketchCurveSegment(target: selection.decodedTarget())
        )
    }
}
