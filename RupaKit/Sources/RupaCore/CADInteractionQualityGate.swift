public enum CADInteractionQualityGate: String, Codable, CaseIterable, Equatable, Sendable {
    case referenceContract
    case sourceOwnership
    case commandContract
    case selectionTopology
    case viewportAffordance
    case inspectorAffordance
    case agentParity
    case measurementDiagnostics
    case verification
    case performanceBudget
}
