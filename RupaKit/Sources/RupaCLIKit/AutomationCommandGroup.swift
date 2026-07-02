import ArgumentParser

public struct AutomationCommandGroup: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "command",
        abstract: "Apply typed AutomationCommand payloads.",
        subcommands: [
            ApplyAutomationCommand.self,
            DescribeDocumentCommand.self,
            SetDisplayUnitCommand.self,
            SetRulerConfigurationCommand.self,
            SetWorkspaceScalePresetCommand.self,
            FitWorkspaceScaleCommand.self,
            SetViewportGridCommand.self,
            RebaseWorkspaceOriginCommand.self,
        ],
        defaultSubcommand: ApplyAutomationCommand.self
    )

    public init() {}
}
