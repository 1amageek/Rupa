import Foundation
import RupaCore

/// A closed, transient viewport operation. It never publishes project data.
public enum AgentViewportOperation: Codable, Equatable, Sendable {
    case fitVisible
    case fitSelected
    case orbit(yawDeltaDegrees: Double, elevationDeltaDegrees: Double)
    case pan(deltaXPoints: Double, deltaYPoints: Double)
    case zoom(factor: Double)
    case setOrientation(AgentViewportOrientation)
    case setProjection(AgentViewportProjection)
    case resetCamera
    case setDisplayMode(AgentViewportDisplayMode)

    private enum CodingKeys: String, CodingKey {
        case kind
        case yawDeltaDegrees
        case elevationDeltaDegrees
        case deltaXPoints
        case deltaYPoints
        case factor
        case orientation
        case projection
        case displayMode
    }

    public func validate() throws {
        switch self {
        case .fitVisible, .fitSelected, .resetCamera:
            break
        case let .orbit(yawDeltaDegrees, elevationDeltaDegrees):
            try Self.validateFinite(yawDeltaDegrees, name: "yawDeltaDegrees")
            try Self.validateFinite(elevationDeltaDegrees, name: "elevationDeltaDegrees")
        case let .pan(deltaXPoints, deltaYPoints):
            try Self.validateFinite(deltaXPoints, name: "deltaXPoints")
            try Self.validateFinite(deltaYPoints, name: "deltaYPoints")
        case let .zoom(factor):
            try Self.validateFinite(factor, name: "factor")
            guard factor > 0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Viewport zoom factor must be greater than zero."
                )
            }
        case let .setOrientation(orientation):
            guard orientation != .custom else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Viewport orientation custom is state-only."
                )
            }
        case .setDisplayMode, .setProjection:
            break
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "fitVisible":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind"])
            self = .fitVisible
        case "fitSelected":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind"])
            self = .fitSelected
        case "orbit":
            try Self.rejectKeys(
                from: decoder,
                allowedKeys: ["kind", "yawDeltaDegrees", "elevationDeltaDegrees"]
            )
            self = .orbit(
                yawDeltaDegrees: try container.decode(Double.self, forKey: .yawDeltaDegrees),
                elevationDeltaDegrees: try container.decode(Double.self, forKey: .elevationDeltaDegrees)
            )
        case "pan":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind", "deltaXPoints", "deltaYPoints"])
            self = .pan(
                deltaXPoints: try container.decode(Double.self, forKey: .deltaXPoints),
                deltaYPoints: try container.decode(Double.self, forKey: .deltaYPoints)
            )
        case "zoom":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind", "factor"])
            self = .zoom(factor: try container.decode(Double.self, forKey: .factor))
        case "setOrientation":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind", "orientation"])
            self = .setOrientation(try container.decode(AgentViewportOrientation.self, forKey: .orientation))
        case "resetCamera":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind"])
            self = .resetCamera
        case "setProjection":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind", "projection"])
            self = .setProjection(try container.decode(AgentViewportProjection.self, forKey: .projection))
        case "setDisplayMode":
            try Self.rejectKeys(from: decoder, allowedKeys: ["kind", "displayMode"])
            self = .setDisplayMode(try container.decode(AgentViewportDisplayMode.self, forKey: .displayMode))
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Unsupported viewport operation kind: \(kind)."
            )
        }
        try validate()
    }

    private static func rejectKeys(from decoder: Decoder, allowedKeys: Set<String>) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: allowedKeys)
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fitVisible:
            try container.encode("fitVisible", forKey: .kind)
        case .fitSelected:
            try container.encode("fitSelected", forKey: .kind)
        case let .orbit(yawDeltaDegrees, elevationDeltaDegrees):
            try container.encode("orbit", forKey: .kind)
            try container.encode(yawDeltaDegrees, forKey: .yawDeltaDegrees)
            try container.encode(elevationDeltaDegrees, forKey: .elevationDeltaDegrees)
        case let .pan(deltaXPoints, deltaYPoints):
            try container.encode("pan", forKey: .kind)
            try container.encode(deltaXPoints, forKey: .deltaXPoints)
            try container.encode(deltaYPoints, forKey: .deltaYPoints)
        case let .zoom(factor):
            try container.encode("zoom", forKey: .kind)
            try container.encode(factor, forKey: .factor)
        case let .setOrientation(orientation):
            try container.encode("setOrientation", forKey: .kind)
            try container.encode(orientation, forKey: .orientation)
        case .resetCamera:
            try container.encode("resetCamera", forKey: .kind)
        case let .setProjection(projection):
            try container.encode("setProjection", forKey: .kind)
            try container.encode(projection, forKey: .projection)
        case let .setDisplayMode(displayMode):
            try container.encode("setDisplayMode", forKey: .kind)
            try container.encode(displayMode, forKey: .displayMode)
        }
    }

    private static func validateFinite(_ value: Double, name: String) throws {
        guard value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport \(name) must be finite."
            )
        }
    }
}
