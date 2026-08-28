import Foundation

public enum CADCandidateDecision: Codable, Equatable, Hashable, Sendable {
    case action(CADCandidateAction)
    case unsupported(CADUnsupportedDeclaration)
    case finish(CADOutputRoleBindings)

    private enum CodingKeys: String, CodingKey {
        case kind
        case action
        case unsupported
        case finish
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "action":
            self = .action(try container.decode(CADCandidateAction.self, forKey: .action))
        case "unsupported":
            self = .unsupported(
                try container.decode(CADUnsupportedDeclaration.self, forKey: .unsupported)
            )
        case "finish":
            self = .finish(try container.decode(CADOutputRoleBindings.self, forKey: .finish))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown candidate decision kind: \(kind)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let action):
            try container.encode("action", forKey: .kind)
            try container.encode(action, forKey: .action)
        case .unsupported(let declaration):
            try container.encode("unsupported", forKey: .kind)
            try container.encode(declaration, forKey: .unsupported)
        case .finish(let bindings):
            try container.encode("finish", forKey: .kind)
            try container.encode(bindings, forKey: .finish)
        }
    }
}
