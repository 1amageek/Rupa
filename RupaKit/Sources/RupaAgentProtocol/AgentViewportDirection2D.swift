import Foundation
import RupaCore

/// One projected screen-axis direction. Rendering owns the source basis.
public struct AgentViewportDirection2D: Codable, Equatable, Sendable {
    public let dx: Double
    public let dy: Double

    private enum CodingKeys: String, CodingKey {
        case dx
        case dy
    }

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(from: decoder, allowedKeys: ["dx", "dy"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dx: try container.decode(Double.self, forKey: .dx),
            dy: try container.decode(Double.self, forKey: .dy)
        )
        try validate(named: "direction")
    }

    public func encode(to encoder: Encoder) throws {
        try validate(named: "direction")
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dx, forKey: .dx)
        try container.encode(dy, forKey: .dy)
    }

    public func validate(named name: String) throws {
        guard dx.isFinite, dy.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport \(name) direction must contain finite values."
            )
        }
    }
}
