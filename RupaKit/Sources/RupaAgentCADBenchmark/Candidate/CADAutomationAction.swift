import Foundation

public enum CADAutomationAction: Codable, Equatable, Hashable, Sendable {
    case sketch(CADSketchAction)
    case solid(CADSolidAction)
    case transform(CADTransformAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sketch
        case solid
        case transform
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "sketch":
            self = .sketch(try container.decode(CADSketchAction.self, forKey: .sketch))
        case "solid":
            self = .solid(try container.decode(CADSolidAction.self, forKey: .solid))
        case "transform":
            self = .transform(try container.decode(CADTransformAction.self, forKey: .transform))
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
        case .transform(let transform):
            try container.encode("transform", forKey: .kind)
            try container.encode(transform, forKey: .transform)
        }
    }
}
