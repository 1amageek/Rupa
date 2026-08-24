import RupaCoreTypes

struct MeshUndirectedEdgeKey: Hashable, Sendable {
    let first: MeshVertexID
    let second: MeshVertexID

    init(first: MeshVertexID, second: MeshVertexID) {
        self.first = min(first, second)
        self.second = max(first, second)
    }
}
