import Foundation

public enum PolygonSizingMode: String, Codable, Equatable, Sendable {
    case circumradius
    case inradius

    public var statusTitle: String {
        switch self {
        case .circumradius:
            "Circumscribed"
        case .inradius:
            "Inscribed"
        }
    }

    public func circumradius(from radiusMeters: Double, sides: Int) -> Double {
        switch self {
        case .circumradius:
            return radiusMeters
        case .inradius:
            return radiusMeters / cos(Double.pi / Double(sides))
        }
    }

    public func sideLength(from radiusMeters: Double, sides: Int) -> Double {
        switch self {
        case .circumradius:
            return radiusMeters * 2.0 * sin(Double.pi / Double(sides))
        case .inradius:
            return radiusMeters * 2.0 * tan(Double.pi / Double(sides))
        }
    }

    public func vertexRotationOffsetRadians(sides: Int) -> Double {
        switch self {
        case .circumradius:
            0.0
        case .inradius:
            Double.pi / Double(sides)
        }
    }
}
