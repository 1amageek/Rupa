import ArgumentParser
import RupaAutomation
import RupaCore

public struct SketchCutCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "cut",
        abstract: "Cut a supported source sketch curve with another source curve."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @OptionGroup
    public var selection: CLISelectionTargetOptions

    @Option(help: "Cutter SelectionTarget JSON object.")
    public var cutter: String?

    @Option(help: "JSON file containing one cutter SelectionTarget object.")
    public var cutterFile: String?

    @Flag(help: "Extend a supported line cutter for the intersection solve.")
    public var extendsCutter: Bool = false

    @Flag(help: "Reserve screen-space direction semantics for compatible cut tools.")
    public var usesScreenSpaceDirection: Bool = false

    public init() {}

    public func run() throws {
        try CLIAutomationCommandRunner.run(
            document: document,
            command: .cutSketchCurve(
                target: selection.decodedTarget(),
                cutter: try decodedCutter(),
                options: CutCurveOptions(
                    extendsCutter: extendsCutter,
                    usesScreenSpaceDirection: usesScreenSpaceDirection
                )
            )
        )
    }

    private func decodedCutter() throws -> SelectionTarget {
        try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: cutter,
            filePath: cutterFile,
            valueName: "Cutter SelectionTarget"
        )
    }
}
