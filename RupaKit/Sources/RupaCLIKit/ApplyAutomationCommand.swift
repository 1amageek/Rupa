import ArgumentParser
import RupaAutomation

public struct ApplyAutomationCommand: ParsableCommand {
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

    public func run() throws {
        let sessionID = try document.resolvedSessionID()
        let automationCommand: AutomationCommand = try CLISelectionInputParser.decodeSingleSelectionInput(
            inlinePayload: command,
            filePath: commandFile,
            valueName: "AutomationCommand"
        )

        try CLIExitCode.run {
            let response = try CLIService().applyAutomationCommand(
                target: document.target(sessionID: sessionID),
                command: automationCommand,
                mode: document.mode,
                expectedGeneration: document.generation(),
                dryRun: document.dryRun,
                forceFileEdit: document.forceFileEdit,
                client: document.agentClient(sessionID: sessionID)
            )
            try CLIOutput.write(response: response, asJSON: document.json)
        }
    }
}
