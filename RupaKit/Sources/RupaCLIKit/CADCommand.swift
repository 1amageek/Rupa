import ArgumentParser

/// Groups the semantic CAD commands that use the project access API.
public struct CADCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "cad",
        abstract: "Invoke semantic CAD operations through the active Rupa project.",
        subcommands: [
            CADInvokeCommand.self,
            CADProgramCommand.self,
        ]
    )

    public init() {}
}
