import RupaCore

public struct ViewportSurfaceAnalysisOptions: Equatable, Sendable {
    public var showsCurvatureCombs: Bool
    public var showsPrincipalDirections: Bool
    public var showsTrimBoundaries: Bool
    public var sampleDensity: SurfaceAnalysisSampleDensity
    /// The curvature combs' length relative to their automatic one (the longest tooth a sixth of
    /// the view's diagonal): Square's Scale.
    public var combScale: Double

    public init(
        showsCurvatureCombs: Bool = true,
        showsPrincipalDirections: Bool = true,
        showsTrimBoundaries: Bool = true,
        sampleDensity: SurfaceAnalysisSampleDensity = .standard,
        combScale: Double = 1
    ) {
        self.showsCurvatureCombs = showsCurvatureCombs
        self.showsPrincipalDirections = showsPrincipalDirections
        self.showsTrimBoundaries = showsTrimBoundaries
        self.sampleDensity = sampleDensity
        self.combScale = combScale
    }

    public var showsAnyOverlay: Bool {
        showsCurvatureCombs || showsPrincipalDirections || showsTrimBoundaries
    }

    public var analysisOptions: SurfaceAnalysisOptions {
        SurfaceAnalysisOptions(sampleDensity: sampleDensity)
    }
}
