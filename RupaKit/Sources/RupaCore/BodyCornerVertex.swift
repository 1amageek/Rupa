import Foundation

public enum BodyCornerVertex: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case frontBottomLeft
    case frontBottomRight
    case frontTopRight
    case frontTopLeft
    case backBottomLeft
    case backBottomRight
    case backTopRight
    case backTopLeft
}
