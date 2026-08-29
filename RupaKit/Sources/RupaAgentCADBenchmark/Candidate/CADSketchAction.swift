import Foundation

public enum CADSketchAction: Codable, Equatable, Hashable, Sendable {
    case line(name: String, plane: CADSketchPlane, start: CADPoint3D, end: CADPoint3D)
    case rectangle(
        name: String,
        plane: CADSketchPlane,
        center: CADPoint3D,
        width: CADLength,
        height: CADLength
    )
    case circle(
        name: String,
        plane: CADSketchPlane,
        center: CADPoint3D,
        radius: CADLength
    )
    case angle(
        name: String,
        plane: CADSketchPlane,
        firstStart: CADPoint3D,
        firstEnd: CADPoint3D,
        secondStart: CADPoint3D,
        secondEnd: CADPoint3D
    )
    case constraint(CADConstraintAction)

    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case plane
        case start
        case end
        case center
        case width
        case height
        case radius
        case firstStart
        case firstEnd
        case secondStart
        case secondEnd
        case constraint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "line":
            self = .line(
                name: try container.decode(String.self, forKey: .name),
                plane: try container.decode(CADSketchPlane.self, forKey: .plane),
                start: try container.decode(CADPoint3D.self, forKey: .start),
                end: try container.decode(CADPoint3D.self, forKey: .end)
            )
        case "rectangle":
            self = .rectangle(
                name: try container.decode(String.self, forKey: .name),
                plane: try container.decode(CADSketchPlane.self, forKey: .plane),
                center: try container.decode(CADPoint3D.self, forKey: .center),
                width: try container.decode(CADLength.self, forKey: .width),
                height: try container.decode(CADLength.self, forKey: .height)
            )
        case "circle":
            self = .circle(
                name: try container.decode(String.self, forKey: .name),
                plane: try container.decode(CADSketchPlane.self, forKey: .plane),
                center: try container.decode(CADPoint3D.self, forKey: .center),
                radius: try container.decode(CADLength.self, forKey: .radius)
            )
        case "angle":
            self = .angle(
                name: try container.decode(String.self, forKey: .name),
                plane: try container.decode(CADSketchPlane.self, forKey: .plane),
                firstStart: try container.decode(CADPoint3D.self, forKey: .firstStart),
                firstEnd: try container.decode(CADPoint3D.self, forKey: .firstEnd),
                secondStart: try container.decode(CADPoint3D.self, forKey: .secondStart),
                secondEnd: try container.decode(CADPoint3D.self, forKey: .secondEnd)
            )
        case "constraint":
            self = .constraint(
                try container.decode(CADConstraintAction.self, forKey: .constraint)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown sketch action kind: \(kind)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .line(name, plane, start, end):
            try container.encode("line", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(plane, forKey: .plane)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case let .rectangle(name, plane, center, width, height):
            try container.encode("rectangle", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(plane, forKey: .plane)
            try container.encode(center, forKey: .center)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
        case let .circle(name, plane, center, radius):
            try container.encode("circle", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(plane, forKey: .plane)
            try container.encode(center, forKey: .center)
            try container.encode(radius, forKey: .radius)
        case let .angle(name, plane, firstStart, firstEnd, secondStart, secondEnd):
            try container.encode("angle", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(plane, forKey: .plane)
            try container.encode(firstStart, forKey: .firstStart)
            try container.encode(firstEnd, forKey: .firstEnd)
            try container.encode(secondStart, forKey: .secondStart)
            try container.encode(secondEnd, forKey: .secondEnd)
        case .constraint(let constraint):
            try container.encode("constraint", forKey: .kind)
            try container.encode(constraint, forKey: .constraint)
        }
    }
}
