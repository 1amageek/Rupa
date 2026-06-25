import ArgumentParser
import RupaAutomation

public struct SketchTrimCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "trim",
        abstract: "Trim a supported source sketch curve segment."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISketchEditTargetOptions

    public init() {}

    public func run() throws {
        try CLISketchEditCommandRunner.run(
            document: document,
            command: .trimSketchCurveSegment(target: selection.decodedTarget())
        )
    }
}
