public enum CADInteractionQualityArea: String, Codable, CaseIterable, Equatable, Sendable {
    case selection
    case sketchPrecision
    case snapping
    case constructionGeometry
    case dimensions
    case sweep
    case surfaceModeling
    case curveContinuity
    case agentOperability
    case performance
}
