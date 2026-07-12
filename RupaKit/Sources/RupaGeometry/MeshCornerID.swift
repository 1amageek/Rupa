import Foundation

public struct MeshCornerID: Codable, Comparable, Hashable, Sendable {
    public var rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: MeshCornerID, rhs: MeshCornerID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
