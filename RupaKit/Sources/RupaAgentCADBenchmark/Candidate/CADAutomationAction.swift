import Foundation

public enum CADAutomationAction: Codable, Equatable, Hashable, Sendable {
    case sketch(CADSketchAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sketch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        guard kind == "sketch" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown automation action kind: \(kind)."
            )
        }
        self = .sketch(try container.decode(CADSketchAction.self, forKey: .sketch))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("sketch", forKey: .kind)
        if case .sketch(let sketch) = self {
            try container.encode(sketch, forKey: .sketch)
        }
    }
}
