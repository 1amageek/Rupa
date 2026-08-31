import ArgumentParser
import RupaCore

extension SurfaceAnalysisSampleDensity: ExpressibleByArgument {}

public struct InspectSurfacesCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "surfaces",
        abstract: "Return B-spline surface samples, curvature combs, and trim-boundary analysis."
    )

    @OptionGroup
    public var options: CLIReadDocumentOptions

    @Option(help: "Surface sample density: low, standard, or high.")
    public var sampleDensity: SurfaceAnalysisSampleDensity = .standard

    public init() {}

    public func run() async throws {
        let id = try options.resolvedSessionID()

        try await CLIExitCode.run {
            let envelope = try await CLIService().read(
                target: options.target(sessionID: id),
                mode: options.mode,
                expectedGeneration: options.generation()
            ) { sessionID in
                .surfaceAnalysis(
                    sessionID: sessionID,
                    options: SurfaceAnalysisOptions(sampleDensity: sampleDensity),
                    expectedGeneration: options.generation()
                )
            }
            let response = try CLIResponseProjector.surfaces(envelope)
            try CLIOutput.write(response: response, asJSON: options.json)
        }
    }
}
