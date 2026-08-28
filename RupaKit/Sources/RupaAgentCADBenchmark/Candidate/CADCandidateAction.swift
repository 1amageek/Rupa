import Foundation

public enum CADCandidateAction: Codable, Equatable, Hashable, Sendable {
    case automation(CADAutomationAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case automation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        guard kind == "automation" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown candidate action kind: \(kind)."
            )
        }
        self = .automation(try container.decode(CADAutomationAction.self, forKey: .automation))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("automation", forKey: .kind)
        if case .automation(let action) = self {
            try container.encode(action, forKey: .automation)
        }
    }
}
