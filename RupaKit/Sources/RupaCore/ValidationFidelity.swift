public enum ValidationFidelity: String, Codable, Equatable, Hashable, Sendable {
    case exact
    case conservativeEstimate
    case sampledApproximation
    case heuristic
}
