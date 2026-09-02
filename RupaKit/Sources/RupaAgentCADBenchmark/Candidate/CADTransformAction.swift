import Foundation

/// Typed source recipe used by a transform program.
///
/// The source is part of the candidate intent so a transform never depends on
/// a fixture, a prior session, or an invented persistent identity.
public enum CADTransformSourceAction: Codable, Equatable, Hashable, Sendable {
    case sketch(CADSketchAction)
    case solid(CADSolidAction)

    private enum CodingKeys: String, CodingKey { case kind, sketch, solid }
    private enum Kind: String, Codable { case sketch, solid }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .sketch:
            self = .sketch(try container.decode(CADSketchAction.self, forKey: .sketch))
        case .solid:
            self = .solid(try container.decode(CADSolidAction.self, forKey: .solid))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sketch(let action):
            try container.encode(Kind.sketch, forKey: .kind)
            try container.encode(action, forKey: .sketch)
        case .solid(let action):
            try container.encode(Kind.solid, forKey: .kind)
            try container.encode(action, forKey: .solid)
        }
    }
}

/// Candidate action for changing the placement of a typed source geometry.
public struct CADTransformAction: Codable, Equatable, Hashable, Sendable {
    public let source: CADTransformSourceAction
    public let translation: CADPoint3D
    public let axisPoint: CADPoint3D
    public let rotationAxis: CADDirection3D
    public let rotation: CADAngle

    public init(
        source: CADTransformSourceAction,
        translation: CADPoint3D,
        axisPoint: CADPoint3D,
        rotationAxis: CADDirection3D,
        rotation: CADAngle
    ) {
        self.source = source
        self.translation = translation
        self.axisPoint = axisPoint
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }

}
