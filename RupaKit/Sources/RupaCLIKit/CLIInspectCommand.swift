import ArgumentParser

public struct InspectCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect source and generated CAD references for automation workflows.",
        subcommands: [
            InspectConstructionPlanesCommand.self,
            InspectSketchesCommand.self,
            InspectTopologyCommand.self,
            InspectCurvesCommand.self,
            InspectSnapCommand.self,
            InspectSelectionMeasurementCommand.self,
            InspectSurfacesCommand.self,
            InspectSurfaceFramesCommand.self,
            InspectSurfaceContinuityCommand.self,
        ],
        defaultSubcommand: InspectTopologyCommand.self
    )

    public init() {}
}
