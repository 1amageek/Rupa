import Foundation

public enum SketchEntityPointHandle: String, Codable, Equatable, Hashable, Sendable {
    case point
    case lineStart
    case lineEnd
    case circleCenter
    case arcCenter
    case arcStart
    case arcEnd
}
