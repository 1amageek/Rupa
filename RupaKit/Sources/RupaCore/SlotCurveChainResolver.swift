import SwiftCAD

struct SlotCurveChainResolver: Sendable {
    struct PathSegment: Equatable, Sendable {
        var entityID: SketchEntityID
        var startReference: SketchReference
        var endReference: SketchReference
    }

    func resolve(
        sketch: Sketch,
        selectedEntityID: SketchEntityID
    ) throws -> [PathSegment] {
        guard isSupportedCurveEntity(selectedEntityID, in: sketch) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot curve-chain resolution requires a selected source line or arc target."
            )
        }

        let endpointReferences = curveEndpointReferences(in: sketch)
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

        let edges = try curveEdges(in: sketch, parent: &parent)
        let selectedEdge = try selectedCurveEdge(selectedEntityID, edges: edges)
        let componentIDs = connectedCurveIDs(startingAt: selectedEntityID, edges: edges)
        let componentEdges = edges.filter { componentIDs.contains($0.entityID) }
        let degrees = vertexDegrees(for: componentEdges)

        if degrees.values.contains(where: { $0 > 2 }) {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot source curve chain must not branch."
            )
        }
        let endpoints = degrees.filter { $0.value == 1 }.map(\.key)
        guard endpoints.isEmpty == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires an open curve; closed curve chains are not supported."
            )
        }
        guard endpoints.count == 2 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires one connected open curve chain."
            )
        }

        let startVertex = endpoints.contains(selectedEdge.startVertex) ? selectedEdge.startVertex : endpoints[0]
        return try orderedPathSegments(
            startVertex: startVertex,
            componentIDs: componentIDs,
            edges: edges
        )
    }

    private func isSupportedCurveEntity(
        _ entityID: SketchEntityID,
        in sketch: Sketch
    ) -> Bool {
        guard let entity = sketch.entities[entityID] else {
            return false
        }
        switch entity {
        case .line, .arc:
            return true
        case .point, .circle, .spline:
            return false
        }
    }

    private func curveEndpointReferences(in sketch: Sketch) -> [SketchReference] {
        sketch.entities.flatMap { entityID, entity -> [SketchReference] in
            switch entity {
            case .line:
                return [.lineStart(entityID), .lineEnd(entityID)]
            case .arc:
                return [.arcStart(entityID), .arcEnd(entityID)]
            case .point, .circle, .spline:
                return []
            }
        }
    }

    private func curveEdges(
        in sketch: Sketch,
        parent: inout ParentMap
    ) throws -> [CurveEdge] {
        try sketch.entities.compactMap { entityID, entity -> CurveEdge? in
            let startReference: SketchReference
            let endReference: SketchReference
            switch entity {
            case .line:
                startReference = .lineStart(entityID)
                endReference = .lineEnd(entityID)
            case .arc:
                startReference = .arcStart(entityID)
                endReference = .arcEnd(entityID)
            case .point, .circle, .spline:
                return nil
            }

            let startVertex = parent.find(startReference)
            let endVertex = parent.find(endReference)
            guard startVertex != endVertex else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Slot source curve segment length must be greater than zero."
                )
            }
            return CurveEdge(
                entityID: entityID,
                startReference: startReference,
                endReference: endReference,
                startVertex: startVertex,
                endVertex: endVertex
            )
        }
    }

    private func selectedCurveEdge(
        _ selectedEntityID: SketchEntityID,
        edges: [CurveEdge]
    ) throws -> CurveEdge {
        guard let edge = edges.first(where: { $0.entityID == selectedEntityID }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot curve-chain resolution requires source line or arc targets."
            )
        }
        return edge
    }

    private func connectedCurveIDs(
        startingAt selectedEntityID: SketchEntityID,
        edges: [CurveEdge]
    ) -> Set<SketchEntityID> {
        var selected: Set<SketchEntityID> = []
        var stack = [selectedEntityID]
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

    private func vertexDegrees(for edges: [CurveEdge]) -> [SketchReference: Int] {
        var degrees: [SketchReference: Int] = [:]
        for edge in edges {
            degrees[edge.startVertex, default: 0] += 1
            degrees[edge.endVertex, default: 0] += 1
        }
        return degrees
    }

    private func orderedPathSegments(
        startVertex: SketchReference,
        componentIDs: Set<SketchEntityID>,
        edges: [CurveEdge]
    ) throws -> [PathSegment] {
        var visited: Set<SketchEntityID> = []
        var currentVertex = startVertex
        var segments: [PathSegment] = []

        while true {
            let nextEdges = edges.filter { edge in
                componentIDs.contains(edge.entityID)
                    && visited.contains(edge.entityID) == false
                    && (edge.startVertex == currentVertex || edge.endVertex == currentVertex)
            }
            guard let edge = nextEdges.first else {
                break
            }
            visited.insert(edge.entityID)
            let nextVertex = edge.otherVertex(currentVertex)
            segments.append(PathSegment(
                entityID: edge.entityID,
                startReference: edge.reference(for: currentVertex),
                endReference: edge.reference(for: nextVertex)
            ))
            currentVertex = nextVertex
        }

        guard visited == componentIDs else {
            throw EditorError(
                code: .commandInvalid,
                message: "Slot requires one connected open curve chain."
            )
        }
        return segments
    }

    private struct CurveEdge: Equatable, Sendable {
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
