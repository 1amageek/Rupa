public struct SurfaceAnalysisOptions: Codable, Equatable, Sendable {
    public var sampleDensity: SurfaceAnalysisSampleDensity

    public init(sampleDensity: SurfaceAnalysisSampleDensity = .standard) {
        self.sampleDensity = sampleDensity
    }

    public var samplesPerDirection: Int {
        sampleDensity.samplesPerDirection
    }
}

public enum SurfaceAnalysisSampleDensity: String, Codable, CaseIterable, Equatable, Sendable {
    case low
    case standard
    case high

    public var samplesPerDirection: Int {
        switch self {
        case .low:
            return 3
        case .standard:
            return 5
        case .high:
            return 9
        }
    }
}
