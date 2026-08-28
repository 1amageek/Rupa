public enum CADOutputRoleSelector: Codable, Equatable, Hashable, Sendable {
    case primary
    case created(index: Int)

    public func validate(caseID: CADBenchmarkCaseID, role: String) throws {
        switch self {
        case .primary:
            return
        case let .created(index):
            guard index >= 0 else {
                throw CADBenchmarkError.invalidBinding(
                    caseID: caseID.rawValue,
                    role: role,
                    reason: "Created feature indexes must be non-negative."
                )
            }
        }
    }

    public func resolveFeatureID(
        from result: CADCandidateStepResult,
        caseID: CADBenchmarkCaseID,
        role: String
    ) throws -> String {
        switch self {
        case .primary:
            guard let featureID = result.primaryFeatureID, !featureID.isEmpty else {
                throw CADBenchmarkError.invalidBinding(
                    caseID: caseID.rawValue,
                    role: role,
                    reason: "The selected step has no primary feature."
                )
            }
            return featureID
        case let .created(index):
            guard index >= 0, index < result.createdFeatureIDs.count else {
                throw CADBenchmarkError.invalidBinding(
                    caseID: caseID.rawValue,
                    role: role,
                    reason: "Created feature index is outside the selected step result."
                )
            }
            return result.createdFeatureIDs[index]
        }
    }
}
