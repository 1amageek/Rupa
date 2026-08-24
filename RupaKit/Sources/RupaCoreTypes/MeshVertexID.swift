public struct MeshVertexID: Codable, Comparable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: MeshVertexID, rhs: MeshVertexID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
