import ArgumentParser
import Foundation
import RupaCore

public struct SurfaceSetKnotMultiplicityCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "set-knot-multiplicity",
        abstract: "Set an editable source-owned B-spline surface knot to an explicit higher multiplicity."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "SelectionReference JSON object for one surface knot.")
    public var reference: String?

    @Option(help: "JSON file containing one SelectionReference object.")
    public var referenceFile: String?

    @Option(parsing: .unconditional, help: "Requested knot multiplicity.")
    public var multiplicity: Int

    public init() {}

    public func run() async throws {
        let knotReference: SelectionReference = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: reference,
            filePath: referenceFile,
            valueName: "SelectionReference"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setSurfaceKnotMultiplicity(
                target: knotReference,
                multiplicity: multiplicity
            )
        )
    }
}
