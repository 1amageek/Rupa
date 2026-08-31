import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetTrimLoopsCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-loops",
        abstract: "Set source-owned direct B-spline surface trim loops from UV p-curve JSON."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one direct B-spline surface reference.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(help: "SurfaceTrimLoop JSON object. Repeat for multiple loops.")
    public var trimLoop: [String] = []

    @Option(help: "JSON file containing one SurfaceTrimLoop object or an array.")
    public var trimLoopsFile: String?

    @Flag(help: "Clear authored trim loops and return to the full rectangular surface domain.")
    public var clear: Bool = false

    public init() {}

    public func run() async throws {
        let surfaceReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )
        let loops: [SurfaceTrimLoop] = try CLISelectionInputParser.decodeSelectionInput(
            inlinePayloads: trimLoop,
            filePath: trimLoopsFile,
            clear: clear,
            valueName: "SurfaceTrimLoop",
            arrayName: "SurfaceTrimLoop"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceTrimLoops(
                target: surfaceReference,
                trimLoops: loops
            )
        )
    }
}
