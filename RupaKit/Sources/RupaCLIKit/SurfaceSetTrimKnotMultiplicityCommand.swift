import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetTrimKnotMultiplicityCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-trim-knot-multiplicity",
        abstract: "Set an editable source-owned B-spline surface trim p-curve knot multiplicity."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one authored B-spline surface trim edge.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "B-spline trim p-curve knot index from surfaceSourceSummary.")
    public var knotIndex: Int

    @Option(parsing: .unconditional, help: "Positive target multiplicity.")
    public var multiplicity: Int

    public init() {}

    public func run() async throws {
        let trimReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceTrimKnotMultiplicity(
                target: trimReference,
                knotIndex: knotIndex,
                multiplicity: multiplicity
            )
        )
    }
}
