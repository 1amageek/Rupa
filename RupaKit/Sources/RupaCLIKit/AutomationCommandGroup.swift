import ArgumentParser

public struct AutomationCommandGroup: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "command",
        abstract: "Apply typed AutomationCommand payloads.",
        subcommands: [
            ApplyAutomationCommand.self,
        ],
        defaultSubcommand: ApplyAutomationCommand.self
    )

    public init() {}
}
