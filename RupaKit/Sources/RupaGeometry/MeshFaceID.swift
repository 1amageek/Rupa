import Foundation

public struct MeshFaceID: Codable, Comparable, Hashable, Sendable {
    public var rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: MeshFaceID, rhs: MeshFaceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
