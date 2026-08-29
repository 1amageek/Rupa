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
    case cylinder(
        name: String,
        baseCenter: CADPoint3D,
        axis: CADDirection3D,
        radius: CADLength,
        depth: CADLength
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case origin
        case width
        case depth
        case height
        case baseCenter
        case axis
        case radius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "box":
            self = .box(
                name: try container.decode(String.self, forKey: .name),
                origin: try container.decode(CADPoint3D.self, forKey: .origin),
                width: try container.decode(CADLength.self, forKey: .width),
                depth: try container.decode(CADLength.self, forKey: .depth),
                height: try container.decode(CADLength.self, forKey: .height)
            )
        case "cylinder":
            self = .cylinder(
                name: try container.decode(String.self, forKey: .name),
                baseCenter: try container.decode(CADPoint3D.self, forKey: .baseCenter),
                axis: try container.decode(CADDirection3D.self, forKey: .axis),
                radius: try container.decode(CADLength.self, forKey: .radius),
                depth: try container.decode(CADLength.self, forKey: .depth)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown solid action kind: \(kind)."
            )
        }
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
        case let .cylinder(name, baseCenter, axis, radius, depth):
            try container.encode("cylinder", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(baseCenter, forKey: .baseCenter)
            try container.encode(axis, forKey: .axis)
            try container.encode(radius, forKey: .radius)
            try container.encode(depth, forKey: .depth)
        }
    }
}
