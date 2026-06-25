import ArgumentParser

public struct InspectCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect source and generated CAD references for automation workflows.",
        subcommands: [
            InspectSketchesCommand.self,
            InspectTopologyCommand.self,
            InspectCurvesCommand.self,
            InspectSurfacesCommand.self,
            InspectSurfaceContinuityCommand.self,
        ],
        defaultSubcommand: InspectTopologyCommand.self
    )

    public init() {}
}
