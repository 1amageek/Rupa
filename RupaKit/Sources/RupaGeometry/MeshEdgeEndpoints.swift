import Foundation

public struct MeshEdgeEndpoints: Codable, Equatable, Hashable, Sendable {
    public var start: MeshVertexID
    public var end: MeshVertexID

    public init(start: MeshVertexID, end: MeshVertexID) {
        self.start = start
        self.end = end
    }
}
