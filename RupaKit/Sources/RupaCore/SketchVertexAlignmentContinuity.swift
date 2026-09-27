public enum SketchVertexAlignmentContinuity: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case g0
    case g1
    case g2

    /// The next continuity Tab steps to, wrapping from G2 to G0.
    public var next: SketchVertexAlignmentContinuity {
        switch self {
        case .g0: .g1
        case .g1: .g2
        case .g2: .g0
        }
    }
}
