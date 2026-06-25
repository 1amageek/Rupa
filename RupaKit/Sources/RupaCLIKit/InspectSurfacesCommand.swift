import ArgumentParser
import RupaCore

extension SurfaceAnalysisSampleDensity: ExpressibleByArgument {}

public struct InspectSurfacesCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surfaces",
        abstract: "Return B-spline surface samples, curvature combs, and trim-boundary analysis."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    @Option(help: "Surface sample density: low, standard, or high.")
    public var sampleDensity: SurfaceAnalysisSampleDensity = .standard

    public init() {}

    public func run() throws {
        let id = try options.resolvedSessionID()

        try CLIExitCode.run {
            let response = try CLIService().surfaceAnalysis(
                target: options.target(sessionID: id),
                options: SurfaceAnalysisOptions(sampleDensity: sampleDensity),
                mode: options.mode,
                expectedGeneration: options.generation(),
                client: options.agentClient(sessionID: id)
            )
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
