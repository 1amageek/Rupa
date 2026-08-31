import ArgumentParser
import RupaAutomation
import RupaCore

public struct FeatureCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "feature",
        abstract: "Edit CAD feature history state.",
        subcommands: [
            FeatureSuppressCommand.self,
            FeatureUnsuppressCommand.self,
        ],
        defaultSubcommand: FeatureSuppressCommand.self
    )

    public init() {}
}

public struct FeatureSuppressCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "suppress",
        abstract: "Suppress an existing CAD feature."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Feature UUID to suppress.")
    public var feature: String

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setFeatureSuppression(
                featureID: try CLIFeatureReferenceParser.featureID(feature, valueName: "Feature"),
                isSuppressed: true
            )
        )
    }
}

public struct FeatureUnsuppressCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "unsuppress",
        abstract: "Unsuppress an existing CAD feature."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Argument(help: "Feature UUID to unsuppress.")
    public var feature: String

    public init() {}

    public func run() async throws {
        try await CLIAutomationCommandRunner.run(
            document: document,
            command: .setFeatureSuppression(
                featureID: try CLIFeatureReferenceParser.featureID(feature, valueName: "Feature"),
                isSuppressed: false
            )
        )
    }
}
