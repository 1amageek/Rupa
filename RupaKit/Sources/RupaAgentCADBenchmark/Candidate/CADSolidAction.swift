import Foundation

/// Candidate action for a solid-producing CAD operation.
public enum CADSolidAction: Codable, Equatable, Hashable, Sendable {
    case box(
        name: String,
        origin: CADPoint3D,
        width: CADLength,
        depth: CADLength,
        height: CADLength
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case origin
        case width
        case depth
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        guard kind == "box" else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown solid action kind: \(kind)."
            )
        }
        self = .box(
            name: try container.decode(String.self, forKey: .name),
            origin: try container.decode(CADPoint3D.self, forKey: .origin),
            width: try container.decode(CADLength.self, forKey: .width),
            depth: try container.decode(CADLength.self, forKey: .depth),
            height: try container.decode(CADLength.self, forKey: .height)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .box(name, origin, width, depth, height):
            try container.encode("box", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(origin, forKey: .origin)
            try container.encode(width, forKey: .width)
            try container.encode(depth, forKey: .depth)
            try container.encode(height, forKey: .height)
        }
    }
}
