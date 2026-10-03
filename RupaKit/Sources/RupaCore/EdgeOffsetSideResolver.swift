import SwiftCAD
import RupaCoreTypes

/// The faces an Offset Edge chain runs over on each side, read from the evaluated body: the
/// edges bounding the support face run over it, and along the chain each further edge runs over
/// its face on the same side — not the face across its neighbour, the neighbour's own face, or
/// else the face meeting the neighbour's along an edge — so a chain across a top and a slope runs
/// over both (Plasticity's Offset Edge).
struct EdgeOffsetSideResolver {
    struct Side: Equatable {
        let edge: EdgeID
        let support: FaceID
        /// The face across the edge from `support`; nil for a sheet's open edge.
        let across: FaceID?
    }

    let model: BRepModel

    func sides(of edges: [EdgeID], startingOn start: FaceID, operationName: String) throws -> [Side] {
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        for faceID in model.faces.keys.sorted() {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] where facesOfEdge[coedge.edgeID]?.contains(faceID) != true {
                    facesOfEdge[coedge.edgeID, default: []].append(faceID)
                }
            }
        }
        func edgesOf(_ face: FaceID) -> Set<EdgeID> {
            Set(model.faces[face]?.loops.flatMap { model.loops[$0]?.coedges.map(\.edgeID) ?? [] } ?? [])
        }
        func vertices(of edge: EdgeID) -> Set<VertexID> {
            guard let model = model.edges[edge] else { return [] }
            return [model.startVertexID, model.endVertexID]
        }
        for edge in edges where (1...2).contains(facesOfEdge[edge]?.count ?? 0) == false {
            throw EditorError(code: .commandInvalid, message: "\(operationName) offsets edges bounding one or two faces.")
        }
        var assigned: [EdgeID: (support: FaceID, across: FaceID?)] = [:]
        for edge in edges {
            let faces = facesOfEdge[edge] ?? []
            if faces.contains(start) { assigned[edge] = (start, faces.first { $0 != start }) }
        }
        guard assigned.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) offsets edges over a support face they bound; an edge does not bound it.")
        }
        var changed = true
        while changed {
            changed = false
            for edge in edges where assigned[edge] == nil {
                let faces = facesOfEdge[edge] ?? []
                for neighbour in edges where vertices(of: neighbour).isDisjoint(with: vertices(of: edge)) == false {
                    guard let side = assigned[neighbour] else { continue }
                    let support: FaceID?
                    if let across = side.across, faces.contains(across) {
                        support = faces.first { $0 != across }
                    } else if faces.contains(side.support) {
                        support = side.support
                    } else {
                        let besideSupport = edgesOf(side.support)
                        support = faces.first { edgesOf($0).isDisjoint(with: besideSupport) == false }
                    }
                    guard let support else { continue }
                    assigned[edge] = (support, faces.first { $0 != support })
                    changed = true
                    break
                }
            }
        }
        return try edges.map { edge in
            guard let side = assigned[edge] else {
                throw EditorError(code: .commandInvalid, message: "\(operationName) offsets a chain of edges from the support face; an edge does not continue it.")
            }
            return Side(edge: edge, support: side.support, across: side.across)
        }
    }
}
