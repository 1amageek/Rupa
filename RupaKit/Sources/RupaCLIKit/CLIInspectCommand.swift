import ArgumentParser

public struct InspectCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect source and generated CAD references for automation workflows.",
        subcommands: [
            InspectConstructionPlanesCommand.self,
            InspectSceneGraphCommand.self,
            InspectViewportCommand.self,
            InspectSketchesCommand.self,
            InspectTopologyCommand.self,
            InspectCurvesCommand.self,
            InspectSnapCommand.self,
            InspectSelectionMeasurementCommand.self,
            InspectSurfacesCommand.self,
            InspectSurfaceFramesCommand.self,
            InspectSurfaceContinuityCommand.self,
            InspectSurfaceBoundaryContinuityCompatibilityCommand.self,
        ],
        defaultSubcommand: InspectTopologyCommand.self
    )

    public init() {}
}
