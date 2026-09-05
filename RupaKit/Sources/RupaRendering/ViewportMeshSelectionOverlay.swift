import Foundation
import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene

/// Immutable world-space geometry for one Authored Mesh selection overlay.
///
/// The builder consumes one evaluated presentation item and never changes the
/// source or project authority. `selectedElements` remains the complete caller
/// selection even when the derived boundary display is visibly limited.
public struct ViewportMeshSelectionOverlay: Equatable, Sendable {
    private static let maximumVisibleSegmentCount = 2_048

    public struct Point: Equatable, Sendable {
        public let element: MeshSelectionElement
        public let vertexID: MeshVertexID
        public let sourcePosition: GeometryPoint3D
        public let position: GeometryPoint3D

        public init(
            element: MeshSelectionElement,
            vertexID: MeshVertexID,
            sourcePosition: GeometryPoint3D,
            position: GeometryPoint3D
        ) {
            self.element = element
            self.vertexID = vertexID
            self.sourcePosition = sourcePosition
            self.position = position
        }
    }

    public struct BoundarySegment: Equatable, Sendable {
        public let edgeID: MeshEdgeID
        public let startVertexID: MeshVertexID
        public let endVertexID: MeshVertexID
        public let start: GeometryPoint3D
        public let end: GeometryPoint3D

        public init(
            edgeID: MeshEdgeID,
            startVertexID: MeshVertexID,
            endVertexID: MeshVertexID,
            start: GeometryPoint3D,
            end: GeometryPoint3D
        ) {
            self.edgeID = edgeID
            self.startVertexID = startVertexID
            self.endVertexID = endVertexID
            self.start = start
            self.end = end
        }
    }

    public enum BuildError: Error, Equatable, LocalizedError, Sendable {
        case unsupportedSource
        case invalidSource
        case invalidSelection
        case invalidBoundary
        case invalidLimit
        case selectionLimitExceeded

        public var errorDescription: String? {
            switch self {
            case .unsupportedSource:
                "Mesh selection overlays require an Authored Mesh presentation source."
            case .invalidSource:
                "The Mesh source cannot be indexed for selection overlay construction."
            case .invalidSelection:
                "A selected Mesh element is not present in the presentation source."
            case .invalidBoundary:
                "A selected Mesh face has an invalid boundary range."
            case .invalidLimit:
                "The visible Mesh selection segment limit is outside the supported range."
            case .selectionLimitExceeded:
                "The Mesh selection contains more elements than the supported selection limit."
            }
        }
    }

    public let snapshotID: EvaluationSnapshotID
    public let sourceReference: GeometrySourceReference
    public let sourceID: GeometrySourceID
    public let occurrenceID: SceneOccurrenceID
    public let selectedElements: [MeshSelectionElement]
    public let points: [Point]
    public let boundarySegments: [BoundarySegment]
    public let sourceBoundarySegmentCount: Int
    public let visibleBoundarySegmentCount: Int
    public let isTruncated: Bool

    public var omittedBoundarySegmentCount: Int {
        max(0, sourceBoundarySegmentCount - visibleBoundarySegmentCount)
    }

    public init(
        snapshotID: EvaluationSnapshotID,
        sourceReference: GeometrySourceReference,
        sourceID: GeometrySourceID,
        occurrenceID: SceneOccurrenceID,
        selectedElements: [MeshSelectionElement],
        points: [Point],
        boundarySegments: [BoundarySegment],
        sourceBoundarySegmentCount: Int,
        visibleBoundarySegmentCount: Int,
        isTruncated: Bool
    ) {
        self.snapshotID = snapshotID
        self.sourceReference = sourceReference
        self.sourceID = sourceID
        self.occurrenceID = occurrenceID
        self.selectedElements = selectedElements
        self.points = points
        self.boundarySegments = boundarySegments
        self.sourceBoundarySegmentCount = sourceBoundarySegmentCount
        self.visibleBoundarySegmentCount = visibleBoundarySegmentCount
        self.isTruncated = isTruncated
    }

    /// Builds one immutable overlay from one presentation item.
    ///
    /// The source is a validated immutable MeshSource. Only requested IDs and
    /// retained boundary endpoints are indexed. Unknown selected IDs are
    /// rejected instead of being silently omitted. Face outlines use the
    /// original corner-edge relationship, never triangulation diagonals.
    public static func build(
        snapshotID: EvaluationSnapshotID,
        item: UniversalViewportSceneItem,
        selectedElements: [MeshSelectionElement],
        maxVisibleSegments: Int = 2_048
    ) throws -> ViewportMeshSelectionOverlay {
        try Task.checkCancellation()
        guard maxVisibleSegments >= 0,
              maxVisibleSegments <= maximumVisibleSegmentCount else {
            throw BuildError.invalidLimit
        }
        guard selectedElements.count <= MeshEditLimits.standard.maxSelectedIDs else {
            throw BuildError.selectionLimitExceeded
        }
        guard case .authoredMesh(let sourceID) = item.sourceReference,
              sourceID == item.mesh.identity else {
            throw BuildError.unsupportedSource
        }

        let mesh = item.mesh
        let visibleLimit = maxVisibleSegments
        var requestedVertexIDs: Set<MeshVertexID> = []
        var requestedEdgeIDs: Set<MeshEdgeID> = []
        var requestedFaceIDs: Set<MeshFaceID> = []
        var requestedCornerIDs: Set<MeshCornerID> = []
        requestedVertexIDs.reserveCapacity(selectedElements.count)
        requestedEdgeIDs.reserveCapacity(selectedElements.count)
        requestedFaceIDs.reserveCapacity(selectedElements.count)
        requestedCornerIDs.reserveCapacity(selectedElements.count)
        for element in selectedElements {
            try Task.checkCancellation()
            switch element {
            case .vertex(let vertexID):
                requestedVertexIDs.insert(vertexID)
            case .edge(let edgeID):
                requestedEdgeIDs.insert(edgeID)
            case .face(let faceID):
                requestedFaceIDs.insert(faceID)
            case .corner(let cornerID):
                requestedCornerIDs.insert(cornerID)
            }
        }

        var cornerVertexByID: [MeshCornerID: MeshVertexID] = [:]
        cornerVertexByID.reserveCapacity(requestedCornerIDs.count)
        if !requestedCornerIDs.isEmpty {
            for index in mesh.cornerIDs.indices {
                try Task.checkCancellation()
                let cornerID = mesh.cornerIDs[index]
                guard requestedCornerIDs.contains(cornerID) else {
                    continue
                }
                guard mesh.cornerVertexIDs.indices.contains(index) else {
                    throw BuildError.invalidSource
                }
                cornerVertexByID[cornerID] = mesh.cornerVertexIDs[index]
            }
            guard cornerVertexByID.count == requestedCornerIDs.count else {
                throw BuildError.invalidSelection
            }
        }
        for vertexID in cornerVertexByID.values {
            requestedVertexIDs.insert(vertexID)
        }

        var faceRangeByID: [MeshFaceID: MeshIndexRange] = [:]
        faceRangeByID.reserveCapacity(requestedFaceIDs.count)
        if !requestedFaceIDs.isEmpty {
            for index in mesh.faceIDs.indices {
                try Task.checkCancellation()
                let faceID = mesh.faceIDs[index]
                guard requestedFaceIDs.contains(faceID) else {
                    continue
                }
                guard mesh.faceCornerRanges.indices.contains(index) else {
                    throw BuildError.invalidSource
                }
                faceRangeByID[faceID] = mesh.faceCornerRanges[index]
            }
            guard faceRangeByID.count == requestedFaceIDs.count else {
                throw BuildError.invalidSelection
            }
        }

        var boundaryEdgeIDs: Set<MeshEdgeID> = []
        boundaryEdgeIDs.reserveCapacity(selectedElements.count)
        var visibleEdgeIDs: [MeshEdgeID] = []
        visibleEdgeIDs.reserveCapacity(visibleLimit)
        var sourceBoundarySegmentCount = 0

        func appendBoundaryEdge(_ edgeID: MeshEdgeID) throws {
            try Task.checkCancellation()
            guard boundaryEdgeIDs.insert(edgeID).inserted else {
                return
            }
            let count = sourceBoundarySegmentCount.addingReportingOverflow(1)
            guard !count.overflow else {
                throw BuildError.invalidSource
            }
            sourceBoundarySegmentCount = count.partialValue
            if visibleEdgeIDs.count < visibleLimit {
                visibleEdgeIDs.append(edgeID)
            }
        }

        for element in selectedElements {
            try Task.checkCancellation()
            switch element {
            case .edge(let edgeID):
                try appendBoundaryEdge(edgeID)
            case .face(let faceID):
                guard let range = faceRangeByID[faceID] else {
                    throw BuildError.invalidSelection
                }
                let end = range.start.addingReportingOverflow(range.count)
                guard range.start >= 0,
                      range.count >= 0,
                      !end.overflow,
                      end.partialValue <= mesh.cornerEdgeIDs.count else {
                    throw BuildError.invalidBoundary
                }
                for cornerIndex in range.start..<end.partialValue {
                    try Task.checkCancellation()
                    guard mesh.cornerEdgeIDs.indices.contains(cornerIndex) else {
                        throw BuildError.invalidBoundary
                    }
                    try appendBoundaryEdge(mesh.cornerEdgeIDs[cornerIndex])
                }
            case .vertex, .corner:
                continue
            }
        }

        var visibleEdgeSet: Set<MeshEdgeID> = []
        visibleEdgeSet.reserveCapacity(visibleEdgeIDs.count)
        visibleEdgeSet.formUnion(visibleEdgeIDs)
        var visibleEdgeEndpoints: [MeshEdgeID: MeshEdgeEndpoints] = [:]
        visibleEdgeEndpoints.reserveCapacity(visibleEdgeIDs.count)
        var unresolvedDirectEdgeIDs = requestedEdgeIDs
        if !requestedEdgeIDs.isEmpty || !visibleEdgeIDs.isEmpty {
            for index in mesh.edgeIDs.indices {
                try Task.checkCancellation()
                let edgeID = mesh.edgeIDs[index]
                if requestedEdgeIDs.contains(edgeID) {
                    unresolvedDirectEdgeIDs.remove(edgeID)
                }
                guard visibleEdgeSet.contains(edgeID) else {
                    continue
                }
                guard mesh.edgeEndpoints.indices.contains(index) else {
                    throw BuildError.invalidSource
                }
                visibleEdgeEndpoints[edgeID] = mesh.edgeEndpoints[index]
            }
        }
        guard unresolvedDirectEdgeIDs.isEmpty else {
            throw BuildError.invalidSelection
        }
        guard visibleEdgeEndpoints.count == visibleEdgeIDs.count else {
            throw BuildError.invalidSource
        }

        for endpoints in visibleEdgeEndpoints.values {
            requestedVertexIDs.insert(endpoints.start)
            requestedVertexIDs.insert(endpoints.end)
        }

        var vertexIndexByID: [MeshVertexID: Int] = [:]
        vertexIndexByID.reserveCapacity(requestedVertexIDs.count)
        if !requestedVertexIDs.isEmpty {
            for index in mesh.vertexIDs.indices {
                try Task.checkCancellation()
                let vertexID = mesh.vertexIDs[index]
                guard requestedVertexIDs.contains(vertexID) else {
                    continue
                }
                guard mesh.vertexPositions.indices.contains(index) else {
                    throw BuildError.invalidSource
                }
                vertexIndexByID[vertexID] = index
            }
        }
        guard vertexIndexByID.count == requestedVertexIDs.count else {
            throw BuildError.invalidSelection
        }

        var transformedPositions: [MeshVertexID: GeometryPoint3D] = [:]
        transformedPositions.reserveCapacity(requestedVertexIDs.count)

        func sourcePosition(for vertexID: MeshVertexID) throws -> GeometryPoint3D {
            guard let index = vertexIndexByID[vertexID], mesh.vertexPositions.indices.contains(index) else {
                throw BuildError.invalidSelection
            }
            return mesh.vertexPositions[index]
        }

        func worldPosition(for vertexID: MeshVertexID) throws -> GeometryPoint3D {
            if let cached = transformedPositions[vertexID] {
                return cached
            }
            try Task.checkCancellation()
            let position: GeometryPoint3D
            do {
                position = try item.worldTransform.applying(to: sourcePosition(for: vertexID))
            } catch {
                throw BuildError.invalidSource
            }
            transformedPositions[vertexID] = position
            return position
        }

        func cornerVertexID(for cornerID: MeshCornerID) throws -> MeshVertexID {
            guard let vertexID = cornerVertexByID[cornerID] else {
                throw BuildError.invalidSelection
            }
            return vertexID
        }

        func boundarySegment(for edgeID: MeshEdgeID) throws -> BoundarySegment {
            guard let endpoints = visibleEdgeEndpoints[edgeID] else {
                throw BuildError.invalidSource
            }
            return BoundarySegment(
                edgeID: edgeID,
                startVertexID: endpoints.start,
                endVertexID: endpoints.end,
                start: try worldPosition(for: endpoints.start),
                end: try worldPosition(for: endpoints.end)
            )
        }

        var points: [Point] = []
        points.reserveCapacity(selectedElements.count)
        var boundarySegments: [BoundarySegment] = []
        boundarySegments.reserveCapacity(visibleEdgeIDs.count)
        for element in selectedElements {
            try Task.checkCancellation()
            switch element {
            case .vertex(let vertexID):
                points.append(Point(
                    element: element,
                    vertexID: vertexID,
                    sourcePosition: try sourcePosition(for: vertexID),
                    position: try worldPosition(for: vertexID)
                ))
            case .corner(let cornerID):
                let vertexID = try cornerVertexID(for: cornerID)
                points.append(Point(
                    element: element,
                    vertexID: vertexID,
                    sourcePosition: try sourcePosition(for: vertexID),
                    position: try worldPosition(for: vertexID)
                ))
            case .edge, .face:
                continue
            }
        }

        for edgeID in visibleEdgeIDs {
            try Task.checkCancellation()
            boundarySegments.append(try boundarySegment(for: edgeID))
        }

        try Task.checkCancellation()
        return ViewportMeshSelectionOverlay(
            snapshotID: snapshotID,
            sourceReference: item.sourceReference,
            sourceID: sourceID,
            occurrenceID: item.occurrenceID,
            selectedElements: selectedElements,
            points: points,
            boundarySegments: boundarySegments,
            sourceBoundarySegmentCount: sourceBoundarySegmentCount,
            visibleBoundarySegmentCount: boundarySegments.count,
            isTruncated: sourceBoundarySegmentCount > boundarySegments.count
        )
    }
}
