import Foundation

public enum CADCandidateAction: Codable, Equatable, Hashable, Sendable {
    case automation(CADAutomationAction)
    case compound(CADCompoundAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case automation
        case compound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "automation":
            self = .automation(try container.decode(CADAutomationAction.self, forKey: .automation))
        case "compound":
            self = .compound(try container.decode(CADCompoundAction.self, forKey: .compound))
        default:
            throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Unknown candidate action kind: \(kind)."
                )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automation(let action):
            try container.encode("automation", forKey: .kind)
            try container.encode(action, forKey: .automation)
        case .compound(let action):
            try container.encode("compound", forKey: .kind)
            try container.encode(action, forKey: .compound)
        }
    }
}
