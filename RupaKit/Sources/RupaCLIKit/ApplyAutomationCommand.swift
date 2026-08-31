import ArgumentParser
import RupaAutomation

public struct ApplyAutomationCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply one AutomationCommand JSON payload to a file or live document."
    )

    @OptionGroup
    public var document: CLIWriteDocumentOptions

    @Option(help: "AutomationCommand JSON object.")
    public var command: String?

    @Option(help: "JSON file containing one AutomationCommand object.")
    public var commandFile: String?

    public init() {}

    public func run() async throws {
        let automationCommand: AutomationCommand = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: command,
            filePath: commandFile,
            valueName: "AutomationCommand"
        )

        try await CLIAutomationCommandRunner.run(
            document: document,
            command: automationCommand
        )
    }
}
