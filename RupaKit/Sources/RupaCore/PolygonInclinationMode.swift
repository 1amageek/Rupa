import Foundation

public enum PolygonInclinationMode: String, Codable, Equatable, Sendable {
    case vertical
    case horizontal

    public var statusTitle: String {
        switch self {
        case .vertical:
            "Vertical"
        case .horizontal:
            "Horizontal"
        }
    }

    public func toggled() -> PolygonInclinationMode {
        switch self {
        case .vertical:
            .horizontal
        case .horizontal:
            .vertical
        }
    }

    public func rotationAngleRadians(
        sides: Int,
        sizingMode: PolygonSizingMode
    ) -> Double {
        constructionPlaneAxisAngleRadians + sizingMode.vertexRotationOffsetRadians(sides: sides)
    }

    private var constructionPlaneAxisAngleRadians: Double {
        switch self {
        case .vertical:
            -Double.pi / 2.0
        case .horizontal:
            0.0
        }
    }
}
