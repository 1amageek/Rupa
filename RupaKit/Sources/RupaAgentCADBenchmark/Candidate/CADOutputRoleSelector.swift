import Foundation

public enum CADOutputRoleSelector: Codable, Equatable, Hashable, Sendable {
    case primary
    case created(index: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case index
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "primary":
            self = .primary
        case "created":
            self = .created(index: try container.decode(Int.self, forKey: .index))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown output role selector kind: \(kind)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .primary:
            try container.encode("primary", forKey: .kind)
        case .created(let index):
            try container.encode("created", forKey: .kind)
            try container.encode(index, forKey: .index)
        }
    }

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
