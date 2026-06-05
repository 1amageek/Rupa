import Foundation

public enum ObjectRepresentationKind: String, Codable, Hashable, Sendable {
    case twoDimensional
    case threeDimensional
    case text

    public var title: String {
        switch self {
        case .twoDimensional:
            "2D"
        case .threeDimensional:
            "3D"
        case .text:
            "Text"
        }
    }
}
