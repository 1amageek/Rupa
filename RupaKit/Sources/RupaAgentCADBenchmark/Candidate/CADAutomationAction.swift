import Foundation

public enum CADAutomationAction: Codable, Equatable, Hashable, Sendable {
    case sketch(CADSketchAction)
    case solid(CADSolidAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sketch
        case solid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "sketch":
            self = .sketch(try container.decode(CADSketchAction.self, forKey: .sketch))
        case "solid":
            self = .solid(try container.decode(CADSolidAction.self, forKey: .solid))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown automation action kind: \(kind)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sketch(let sketch):
            try container.encode("sketch", forKey: .kind)
            try container.encode(sketch, forKey: .sketch)
        case .solid(let solid):
            try container.encode("solid", forKey: .kind)
            try container.encode(solid, forKey: .solid)
        }
    }
}
