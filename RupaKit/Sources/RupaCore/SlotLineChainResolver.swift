import SwiftCAD

struct SlotLineChainResolver: Sendable {
    struct PathVertex: Equatable, Sendable {
        var reference: SketchReference
        var connectedLineEndpointReferences: [SketchReference]
    }

    func resolve(
        sketch: Sketch,
        selectedLineID: SketchEntityID
    ) throws -> [PathVertex] {
        guard case .line = sketch.entities[selectedLineID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot line-chain resolution requires a selected source line target."
            )
        }

        let endpointReferences = lineEndpointReferences(in: sketch)
        var parent = ParentMap()
        for reference in endpointReferences {
            parent.insert(reference)
        }
        for constraint in sketch.constraints {
            guard case .coincident(let first, let second) = constraint else {
                continue
            }
            parent.insert(first)
            parent.insert(second)
            parent.union(first, second)
        }

        let edges = try lineEdges(in: sketch, parent: &parent)
        let selectedEdge = try selectedLineEdge(selectedLineID, edges: edges)
        let componentLineIDs = connectedLineIDs(startingAt: selectedLineID, edges: edges)
        let componentEdges = edges.filter { componentLineIDs.contains($0.entityID) }
        let degrees = vertexDegrees(for: componentEdges)

        if degrees.values.contains(where: { $0 > 2 }) {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot source line chain must not branch."
            )
        }
        let endpoints = degrees.filter { $0.value == 1 }.map(\.key)
        guard endpoints.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; closed line chains are not supported."
            )
        }
        guard endpoints.count == 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires one connected open line chain."
            )
        }

        let startVertex = endpoints.contains(selectedEdge.startVertex) ? selectedEdge.startVertex : endpoints[0]
        return try orderedPathVertices(
            startVertex: startVertex,
            componentLineIDs: componentLineIDs,
            edges: edges,
            parent: &parent
        )
    }

    private func lineEndpointReferences(in sketch: Sketch) -> [SketchReference] {
        sketch.entities.keys.flatMap { entityID in
            [
                SketchReference.lineStart(entityID),
                SketchReference.lineEnd(entityID),
            ]
        }
        .filter { reference in
            switch reference {
            case .lineStart(let entityID), .lineEnd(let entityID):
                if case .line = sketch.entities[entityID] {
                    return true
                }
                return false
            default:
                return false
            }
        }
    }

    private func lineEdges(
        in sketch: Sketch,
        parent: inout ParentMap
    ) throws -> [LineEdge] {
        try sketch.entities.compactMap { entityID, entity -> LineEdge? in
            guard case .line = entity else {
                return nil
            }
            let startReference = SketchReference.lineStart(entityID)
            let endReference = SketchReference.lineEnd(entityID)
            let startVertex = parent.find(startReference)
            let endVertex = parent.find(endReference)
            guard startVertex != endVertex else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source line length must be greater than zero."
                )
            }
            return LineEdge(
                entityID: entityID,
                startReference: startReference,
                endReference: endReference,
                startVertex: startVertex,
                endVertex: endVertex
            )
        }
    }

    private func selectedLineEdge(
        _ selectedLineID: SketchEntityID,
        edges: [LineEdge]
    ) throws -> LineEdge {
        guard let edge = edges.first(where: { $0.entityID == selectedLineID }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot line-chain resolution requires source line targets."
            )
        }
        return edge
    }

    private func connectedLineIDs(
        startingAt selectedLineID: SketchEntityID,
        edges: [LineEdge]
    ) -> Set<SketchEntityID> {
        var selected: Set<SketchEntityID> = []
        var stack = [selectedLineID]
        while let entityID = stack.popLast() {
            guard selected.insert(entityID).inserted,
                  let edge = edges.first(where: { $0.entityID == entityID }) else {
                continue
            }
            for next in edges where selected.contains(next.entityID) == false {
                guard edge.startVertex == next.startVertex
                    || edge.startVertex == next.endVertex
                    || edge.endVertex == next.startVertex
                    || edge.endVertex == next.endVertex else {
                    continue
                }
                stack.append(next.entityID)
            }
        }
        return selected
    }

    private func vertexDegrees(for edges: [LineEdge]) -> [SketchReference: Int] {
        var degrees: [SketchReference: Int] = [:]
        for edge in edges {
            degrees[edge.startVertex, default: 0] += 1
            degrees[edge.endVertex, default: 0] += 1
        }
        return degrees
    }

    private func orderedPathVertices(
        startVertex: SketchReference,
        componentLineIDs: Set<SketchEntityID>,
        edges: [LineEdge],
        parent: inout ParentMap
    ) throws -> [PathVertex] {
        var visited: Set<SketchEntityID> = []
        var currentVertex = startVertex
        var vertices: [PathVertex] = []

        while true {
            let nextEdges = edges.filter { edge in
                componentLineIDs.contains(edge.entityID)
                    && visited.contains(edge.entityID) == false
                    && (edge.startVertex == currentVertex || edge.endVertex == currentVertex)
            }
            guard let edge = nextEdges.first else {
                break
            }
            if vertices.isEmpty {
                vertices.append(pathVertex(for: currentVertex, edges: edges, edge: edge, parent: &parent))
            }
            visited.insert(edge.entityID)
            currentVertex = edge.otherVertex(currentVertex)
            vertices.append(pathVertex(for: currentVertex, edges: edges, edge: edge, parent: &parent))
        }

        guard visited == componentLineIDs else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires one connected open line chain."
            )
        }
        return vertices
    }

    private func pathVertex(
        for vertex: SketchReference,
        edges: [LineEdge],
        edge: LineEdge,
        parent: inout ParentMap
    ) -> PathVertex {
        let reference = edge.reference(for: vertex)
        let connected = edges
            .flatMap { [$0.startReference, $0.endReference] }
            .filter { parent.find($0) == vertex }
        return PathVertex(reference: reference, connectedLineEndpointReferences: connected)
    }

    private struct LineEdge: Equatable, Sendable {
        var entityID: SketchEntityID
        var startReference: SketchReference
        var endReference: SketchReference
        var startVertex: SketchReference
        var endVertex: SketchReference

        func otherVertex(_ vertex: SketchReference) -> SketchReference {
            vertex == startVertex ? endVertex : startVertex
        }

        func reference(for vertex: SketchReference) -> SketchReference {
            vertex == startVertex ? startReference : endReference
        }
    }

    private struct ParentMap {
        private var parents: [SketchReference: SketchReference] = [:]

        mutating func insert(_ reference: SketchReference) {
            parents[reference] = parents[reference] ?? reference
        }

        mutating func find(_ reference: SketchReference) -> SketchReference {
            guard let parent = parents[reference] else {
                parents[reference] = reference
                return reference
            }
            if parent == reference {
                return reference
            }
            let root = find(parent)
            parents[reference] = root
            return root
        }

        mutating func union(_ first: SketchReference, _ second: SketchReference) {
            let firstRoot = find(first)
            let secondRoot = find(second)
            guard firstRoot != secondRoot else {
                return
            }
            parents[secondRoot] = firstRoot
        }
    }
}
