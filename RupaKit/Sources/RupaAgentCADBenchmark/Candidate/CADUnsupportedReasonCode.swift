public enum CADUnsupportedReasonCode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case capabilityUnavailable
    case analyticSphereUnavailable
    case routeNotExposed
}
