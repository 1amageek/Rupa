import RupaCore

public struct ViewportSurfaceAnalysisOptions: Equatable, Sendable {
    public var showsCurvatureCombs: Bool
    public var showsPrincipalDirections: Bool
    public var showsTrimBoundaries: Bool
    public var sampleDensity: SurfaceAnalysisSampleDensity

    public init(
        showsCurvatureCombs: Bool = true,
        showsPrincipalDirections: Bool = true,
        showsTrimBoundaries: Bool = true,
        sampleDensity: SurfaceAnalysisSampleDensity = .standard
    ) {
        self.showsCurvatureCombs = showsCurvatureCombs
        self.showsPrincipalDirections = showsPrincipalDirections
        self.showsTrimBoundaries = showsTrimBoundaries
        self.sampleDensity = sampleDensity
    }

    public var showsAnyOverlay: Bool {
        showsCurvatureCombs || showsPrincipalDirections || showsTrimBoundaries
    }

    public var analysisOptions: SurfaceAnalysisOptions {
        SurfaceAnalysisOptions(sampleDensity: sampleDensity)
    }
}
