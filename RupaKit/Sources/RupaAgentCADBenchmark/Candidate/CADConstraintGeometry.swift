import Foundation

public enum CADConstraintGeometry: Codable, Equatable, Hashable, Sendable {
    case line(start: CADPoint3D, end: CADPoint3D)
    case circle(center: CADPoint3D, radius: CADLength)

    private enum CodingKeys: String, CodingKey {
        case kind
        case start
        case end
        case center
        case radius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "line":
            self = .line(
                start: try container.decode(CADPoint3D.self, forKey: .start),
                end: try container.decode(CADPoint3D.self, forKey: .end)
            )
        case "circle":
            self = .circle(
                center: try container.decode(CADPoint3D.self, forKey: .center),
                radius: try container.decode(CADLength.self, forKey: .radius)
            )
        case let kind:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown constraint geometry kind: \(kind)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .line(start, end):
            try container.encode("line", forKey: .kind)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case let .circle(center, radius):
            try container.encode("circle", forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(radius, forKey: .radius)
        }
    }
}
