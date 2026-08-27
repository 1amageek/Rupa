import Foundation
import RupaCore
import RupaCoreTypes
import RupaProject
import RupaProjectModel

enum ProjectMeshReadSupport {
    static func state(
        for snapshot: ProjectViewSnapshot,
        project: any ProjectOperating,
        operationGuard: @escaping ProjectOperationGuard
    ) async throws -> ProjectStateSnapshot {
        do {
            try operationGuard()
            try Task.checkCancellation()
            let state = try await project.currentState()
            try validate(snapshot: snapshot, state: state)
            _ = try await project.withValidatedCoordinates(
                expectedProjectID: snapshot.projectID,
                expectedDocumentGeneration: snapshot.documentGeneration,
                expectedTransactionRevision: snapshot.transactionRevision,
                expectedPublicationSequence: snapshot.publicationSequence,
                expectedWorkspaceRevision: snapshot.workspaceState.revision,
                operationGuard: operationGuard
            ) {
                true
            }
            return state
        } catch let error as ProjectMeshReadError {
            throw error
        } catch is CancellationError {
            throw ProjectMeshReadError(
                code: .cancelled,
                message: "The project Mesh read was cancelled."
            )
        } catch let error as ProjectControllerError {
            throw ProjectMeshReadError(
                code: readCode(for: error.code),
                message: error.message
            )
        } catch {
            throw ProjectMeshReadError(
                code: .resultMismatch,
                message: "The project Mesh read could not validate its authority coordinates: \(error)."
            )
        }
    }

    static func validate(
        snapshot: ProjectViewSnapshot,
        state: ProjectStateSnapshot
    ) throws {
        guard state.documentLifetimeID == snapshot.documentLifetimeID else {
            throw ProjectMeshReadError(
                code: .documentLifetimeMismatch,
                message: "The project document lifetime no longer matches the supplied view."
            )
        }
        guard state.document.projectID == snapshot.projectID else {
            throw ProjectMeshReadError(
                code: .projectMismatch,
                message: "The current project belongs to a different project ID."
            )
        }
        guard state.documentGeneration == snapshot.documentGeneration else {
            throw ProjectMeshReadError(
                code: .documentGenerationMismatch,
                message: "The project document generation no longer matches the supplied view."
            )
        }
        guard state.transactionRevision == snapshot.transactionRevision else {
            throw ProjectMeshReadError(
                code: .transactionRevisionMismatch,
                message: "The project transaction revision no longer matches the supplied view."
            )
        }
        guard state.publicationSequence == snapshot.publicationSequence else {
            throw ProjectMeshReadError(
                code: .publicationSequenceMismatch,
                message: "The project publication sequence no longer matches the supplied view."
            )
        }
        guard state.workspaceState.revision == snapshot.workspaceState.revision else {
            throw ProjectMeshReadError(
                code: .workspaceRevisionMismatch,
                message: "The project workspace revision no longer matches the supplied view."
            )
        }
    }

    static func validate(
        snapshot: ProjectViewSnapshot,
        handle: ProjectMeshSourceHandle,
        document: DesignDocument
    ) throws {
        let expected = ProjectAuthorityCoordinate(
            projectID: snapshot.projectID,
            transactionRevision: snapshot.transactionRevision,
            publicationSequence: snapshot.publicationSequence
        )
        guard handle.projectAuthorityCoordinate.projectID == expected.projectID else {
            throw ProjectMeshReadError(
                code: .projectMismatch,
                message: "The Mesh source handle belongs to a different project."
            )
        }
        guard handle.projectAuthorityCoordinate.transactionRevision
                == expected.transactionRevision else {
            throw ProjectMeshReadError(
                code: .transactionRevisionMismatch,
                message: "The Mesh source handle belongs to a different transaction revision."
            )
        }
        guard handle.projectAuthorityCoordinate.publicationSequence
                == expected.publicationSequence else {
            throw ProjectMeshReadError(
                code: .publicationSequenceMismatch,
                message: "The Mesh source handle belongs to a different publication sequence."
            )
        }
        guard document.projectID == snapshot.projectID else {
            throw ProjectMeshReadError(
                code: .projectMismatch,
                message: "The snapshot document belongs to a different project."
            )
        }
        guard let asset = document.authoredMeshAssets[handle.sourceID] else {
            throw ProjectMeshReadError(
                code: .sourceMissing,
                message: "The Mesh source is not retained by the project document."
            )
        }
        guard asset.id == handle.sourceID,
              asset.source.identity == handle.sourceID else {
            throw ProjectMeshReadError(
                code: .invalidSource,
                message: "The retained Mesh source identity does not match its asset key."
            )
        }
        guard asset.contentIdentity == handle.contentIdentity else {
            throw ProjectMeshReadError(
                code: .sourceIdentityMismatch,
                message: "The Mesh source content identity no longer matches the handle."
            )
        }
    }

    static func requireAsset(
        for handle: ProjectMeshSourceHandle,
        in document: DesignDocument
    ) throws -> AuthoredMeshAsset {
        guard let asset = document.authoredMeshAssets[handle.sourceID] else {
            throw ProjectMeshReadError(
                code: .sourceMissing,
                message: "The Mesh source is not retained by the project document."
            )
        }
        guard asset.id == handle.sourceID,
              asset.source.identity == handle.sourceID else {
            throw ProjectMeshReadError(
                code: .invalidSource,
                message: "The retained Mesh source identity does not match its asset key."
            )
        }
        guard asset.contentIdentity == handle.contentIdentity else {
            throw ProjectMeshReadError(
                code: .sourceIdentityMismatch,
                message: "The Mesh source content identity no longer matches the handle."
            )
        }
        return asset
    }

    static func readCode(for code: ProjectControllerError.Code) -> ProjectMeshReadError.Code {
        switch code {
        case .projectMismatch:
            .projectMismatch
        case .revisionConflict:
            .transactionRevisionMismatch
        case .publicationConflict:
            .publicationSequenceMismatch
        case .snapshotUnavailable,
             .sourceInvalid,
             .sourceMismatch,
             .transactionInvalid,
             .historyUnavailable,
             .productSourceFailed,
             .cadSourceFailed,
             .projectionFailed,
             .packageFailed,
             .evaluationFailed:
            .resultMismatch
        }
    }

    static func checkedAdd(_ lhs: Int, _ rhs: Int, label: String) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The Mesh read \(label) count overflowed."
            )
        }
        return result.partialValue
    }

    static func checkedMultiply(_ lhs: Int, _ rhs: Int, label: String) throws -> Int {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        guard !result.overflow else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The Mesh read \(label) count overflowed."
            )
        }
        return result.partialValue
    }

    static func catalogReferences(
        in document: DesignDocument,
        budget: inout ProjectMeshReadBudget
    ) throws -> [GeometrySourceID: [ProjectMeshCatalogReference]] {
        var grouped: [GeometrySourceID: [ProjectMeshCatalogReference]] = [:]
        let sceneNodeCount = document.productMetadata.sceneNodes.count
        try budget.consumeScanned(sceneNodeCount, label: "scene node")
        let sceneNodeIDs = document.productMetadata.sceneNodes.keys.sorted()
        for sceneNodeID in sceneNodeIDs {
            try Task.checkCancellation()
            guard let object = document.productMetadata.sceneNodes[sceneNodeID]?.object else {
                continue
            }
            let selection = object.geometryRepresentations.selection
            let representationCount = object.geometryRepresentations.representations.count
            try budget.consumeScanned(representationCount, label: "representation")
            let representationIDs = object.geometryRepresentations.representations.keys.sorted(
                by: { $0.rawValue < $1.rawValue }
            )
            for representationID in representationIDs {
                try Task.checkCancellation()
                guard let representation = object.geometryRepresentations
                    .representations[representationID] else {
                    throw ProjectMeshReadError(
                        code: .invalidSource,
                        message: "A Product Object representation disappeared while building the catalog."
                    )
                }
                guard case .authoredMesh(let sourceID) = representation.source else {
                    continue
                }
                guard document.authoredMeshAssets[sourceID] != nil else {
                    throw ProjectMeshReadError(
                        code: .invalidSource,
                        message: "A Product Object representation references a missing Authored Mesh source."
                    )
                }
                try budget.consumeReferenceUnits(3, label: "catalog reference")
                var selectedPurposes: [GeometryRepresentationPurpose] = []
                if selection?.modeling == representationID {
                    selectedPurposes.append(.modeling)
                }
                if selection?.presentation == representationID {
                    selectedPurposes.append(.presentation)
                }
                grouped[sourceID, default: []].append(
                    ProjectMeshCatalogReference(
                        sceneNodeID: sceneNodeID,
                        representationID: representationID,
                        selectedPurposes: selectedPurposes
                    )
                )
            }
        }
        return grouped
    }
}

struct ProjectMeshReadBudget: Sendable {
    let limits: ProjectMeshReadLimits
    private(set) var scannedRecords = 0
    private(set) var referenceUnits = 0

    init(limits: ProjectMeshReadLimits) {
        self.limits = limits
    }

    mutating func consumeScanned(_ count: Int, label: String) throws {
        guard count >= 0 else {
            throw ProjectMeshReadError(
                code: .invalidLimit,
                message: "The Mesh read \(label) scan count cannot be negative."
            )
        }
        let next = try ProjectMeshReadSupport.checkedAdd(
            scannedRecords,
            count,
            label: "scan"
        )
        guard next <= limits.maxScannedRecords else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The Mesh read \(label) scan exceeds the response limit."
            )
        }
        scannedRecords = next
    }

    mutating func consumeReferenceUnits(_ count: Int, label: String) throws {
        guard count >= 0 else {
            throw ProjectMeshReadError(
                code: .invalidLimit,
                message: "The Mesh read \(label) reference count cannot be negative."
            )
        }
        let next = try ProjectMeshReadSupport.checkedAdd(
            referenceUnits,
            count,
            label: "reference"
        )
        guard next <= limits.maxReferenceUnits else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The Mesh read \(label) references exceed the response limit."
            )
        }
        referenceUnits = next
    }
}

struct ProjectMeshSourceReadWorker: Sendable {
    let handle: ProjectMeshSourceHandle
    let source: MeshSource
    let document: DesignDocument
    let limits: ProjectMeshReadLimits

    func catalog(
        references: [ProjectMeshCatalogReference],
        budget: inout ProjectMeshReadBudget
    ) throws -> ProjectMeshCatalogSource {
        try limits.validate()
        guard let asset = document.authoredMeshAssets[handle.sourceID] else {
            throw ProjectMeshReadError(
                code: .sourceMissing,
                message: "The Mesh source is not retained by the project document."
            )
        }
        guard asset.id == handle.sourceID,
              asset.source.identity == handle.sourceID,
              asset.contentIdentity == handle.contentIdentity else {
            throw ProjectMeshReadError(
                code: .invalidSource,
                message: "The retained Mesh source identity does not match its handle."
            )
        }
        let counts = ProjectMeshElementCounts(
            vertices: source.vertexIDs.count,
            edges: source.edgeIDs.count,
            faces: source.faceIDs.count,
            corners: source.cornerIDs.count
        )
        var elementScanCount = try ProjectMeshReadSupport.checkedAdd(
            counts.vertices,
            counts.edges,
            label: "scan"
        )
        elementScanCount = try ProjectMeshReadSupport.checkedAdd(
            elementScanCount,
            counts.faces,
            label: "scan"
        )
        elementScanCount = try ProjectMeshReadSupport.checkedAdd(
            elementScanCount,
            counts.corners,
            label: "scan"
        )
        try budget.consumeScanned(elementScanCount, label: "source elements")
        let bounds: GeometryBounds3D?
        if source.vertexPositions.isEmpty {
            bounds = nil
        } else {
            try budget.consumeScanned(source.vertexPositions.count, label: "bounds")
            bounds = try source.bounds()
        }
        return ProjectMeshCatalogSource(
            handle: handle,
            provenance: asset.provenance,
            counts: counts,
            bounds: bounds,
            references: references
        )
    }

    func page(
        domain: ProjectMeshElementDomain,
        cursor: ProjectMeshElementCursor?,
        budget: inout ProjectMeshReadBudget
    ) throws -> ProjectMeshElementPage {
        try limits.validate()
        let count = count(for: domain)
        let start: Int
        if let cursor {
            guard cursor.sourceID == handle.sourceID,
                  cursor.contentIdentity == handle.contentIdentity,
                  cursor.domain == domain,
                  cursor.nextIndex >= 0,
                  cursor.nextIndex <= count else {
                throw ProjectMeshReadError(
                    code: .invalidCursor,
                    message: "The Mesh page cursor is not bound to this source, content, domain, or range."
                )
            }
            start = cursor.nextIndex
        } else {
            start = 0
        }
        let requestedCount = min(limits.maxPageRecords, limits.maxOutputRecords)
        let end = min(count, try ProjectMeshReadSupport.checkedAdd(
            start,
            requestedCount,
            label: "page"
        ))
        var records: [ProjectMeshElementRecord] = []
        records.reserveCapacity(end - start)
        for index in start..<end {
            try Task.checkCancellation()
            let recordUnits = try referenceUnits(domain: domain, index: index)
            try budget.consumeReferenceUnits(recordUnits, label: "page record")
            try budget.consumeScanned(recordUnits, label: "page record")
            let record = try makeRecord(domain: domain, index: index, budget: &budget)
            records.append(record)
        }
        let nextCursor: ProjectMeshElementCursor?
        if end < count {
            nextCursor = ProjectMeshElementCursor(
                sourceID: handle.sourceID,
                contentIdentity: handle.contentIdentity,
                domain: domain,
                nextIndex: end
            )
        } else {
            nextCursor = nil
        }
        return ProjectMeshElementPage(
            handle: handle,
            domain: domain,
            records: records,
            nextCursor: nextCursor
        )
    }

    func neighborhood(
        origin: ProjectMeshElementReference,
        depth: Int,
        budget: inout ProjectMeshReadBudget
    ) throws -> ProjectMeshNeighborhood {
        try limits.validate()
        guard depth >= 0 else {
            throw ProjectMeshReadError(
                code: .invalidLimit,
                message: "Mesh neighborhood depth must not be negative."
            )
        }
        guard depth <= limits.maxNeighborhoodDepth else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "Mesh neighborhood depth exceeds the configured limit."
            )
        }
        let index = try makeSourceIndex(budget: &budget)
        guard index.contains(origin) else {
            throw ProjectMeshReadError(
                code: .elementNotFound,
                message: "The Mesh neighborhood origin is not present in the source."
            )
        }
        try Task.checkCancellation()
        let adjacency = index.adjacency
        var distances: [ElementKey: Int] = [ElementKey(origin): 0]
        var queue: [ElementKey] = [ElementKey(origin)]
        var queueIndex = 0
        while queueIndex < queue.count {
            try Task.checkCancellation()
            let current = queue[queueIndex]
            queueIndex += 1
            guard let currentDistance = distances[current], currentDistance < depth else {
                continue
            }
            for neighbor in adjacency[current] ?? [] {
                guard distances[neighbor] == nil else {
                    continue
                }
                distances[neighbor] = currentDistance + 1
                queue.append(neighbor)
                guard queue.count <= limits.maxOutputRecords else {
                    throw ProjectMeshReadError(
                        code: .limitExceeded,
                        message: "The Mesh neighborhood exceeds the output-record limit."
                    )
                }
            }
        }
        let ordered = distances.keys.sorted { lhs, rhs in
            guard let leftDistance = distances[lhs],
                  let rightDistance = distances[rhs] else {
                return false
            }
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }
            if lhs.domain.sortOrder != rhs.domain.sortOrder {
                return lhs.domain.sortOrder < rhs.domain.sortOrder
            }
            return lhs.numericSortValue < rhs.numericSortValue
        }
        guard ordered.count <= limits.maxOutputRecords else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "The Mesh neighborhood exceeds the output-record limit."
            )
        }
        var records: [ProjectMeshNeighborhoodRecord] = []
        records.reserveCapacity(ordered.count)
        for key in ordered {
            try Task.checkCancellation()
            let recordUnits = try referenceUnits(for: key, index: index)
            try budget.consumeReferenceUnits(recordUnits, label: "neighborhood record")
            try budget.consumeScanned(recordUnits, label: "neighborhood record")
            let record = try makeRecord(for: key, index: index)
            guard let distance = distances[key] else {
                throw ProjectMeshReadError(
                    code: .invalidSource,
                    message: "The Mesh neighborhood lost the distance for an included element."
                )
            }
            records.append(
                ProjectMeshNeighborhoodRecord(
                    distance: distance,
                    element: record
                )
            )
        }
        return ProjectMeshNeighborhood(handle: handle, records: records)
    }

    private func count(for domain: ProjectMeshElementDomain) -> Int {
        switch domain {
        case .vertex:
            source.vertexIDs.count
        case .edge:
            source.edgeIDs.count
        case .face:
            source.faceIDs.count
        case .corner:
            source.cornerIDs.count
        }
    }

    private func makeRecord(
        domain: ProjectMeshElementDomain,
        index: Int,
        budget: inout ProjectMeshReadBudget
    ) throws -> ProjectMeshElementRecord {
        switch domain {
        case .vertex:
            return .vertex(
                ProjectMeshVertexRecord(
                    id: source.vertexIDs[index],
                    position: source.vertexPositions[index]
                )
            )
        case .edge:
            return .edge(
                ProjectMeshEdgeRecord(
                    id: source.edgeIDs[index],
                    endpoints: source.edgeEndpoints[index]
                )
            )
        case .face:
            let range = source.faceCornerRanges[index]
            let cornerIDs = Array(source.cornerIDs[range.start..<range.end])
            return .face(
                ProjectMeshFaceRecord(
                    id: source.faceIDs[index],
                    cornerIDs: cornerIDs
                )
            )
        case .corner:
            return try makeCornerRecord(
                cornerIndex: index,
                faceIndex: faceIndex(containingCornerAt: index, budget: &budget)
            )
        }
    }

    private func makeRecord(
        for key: ElementKey,
        index: SourceIndex
    ) throws -> ProjectMeshElementRecord {
        switch key {
        case .vertex(let id):
            guard let elementIndex = index.vertexIndices[id] else {
                throw missingRecord(key)
            }
            return try makeRecordWithoutIndex(domain: .vertex, index: elementIndex)
        case .edge(let id):
            guard let elementIndex = index.edgeIndices[id] else {
                throw missingRecord(key)
            }
            return try makeRecordWithoutIndex(domain: .edge, index: elementIndex)
        case .face(let id):
            guard let elementIndex = index.faceIndices[id] else {
                throw missingRecord(key)
            }
            return try makeRecordWithoutIndex(domain: .face, index: elementIndex)
        case .corner(let id):
            guard let elementIndex = index.cornerIndices[id],
                  let faceIndex = index.faceIndexByCorner[elementIndex] else {
                throw missingRecord(key)
            }
            return try makeCornerRecord(cornerIndex: elementIndex, faceIndex: faceIndex)
        }
    }

    private func makeRecordWithoutIndex(
        domain: ProjectMeshElementDomain,
        index: Int
    ) throws -> ProjectMeshElementRecord {
        switch domain {
        case .vertex:
            return .vertex(
                ProjectMeshVertexRecord(
                    id: source.vertexIDs[index],
                    position: source.vertexPositions[index]
                )
            )
        case .edge:
            return .edge(
                ProjectMeshEdgeRecord(
                    id: source.edgeIDs[index],
                    endpoints: source.edgeEndpoints[index]
                )
            )
        case .face:
            let range = source.faceCornerRanges[index]
            return .face(
                ProjectMeshFaceRecord(
                    id: source.faceIDs[index],
                    cornerIDs: Array(source.cornerIDs[range.start..<range.end])
                )
            )
        case .corner:
            throw ProjectMeshReadError(
                code: .invalidSource,
                message: "Corner records require a precomputed face index."
            )
        }
    }

    private func makeCornerRecord(
        cornerIndex: Int,
        faceIndex: Int
    ) throws -> ProjectMeshElementRecord {
        let range = source.faceCornerRanges[faceIndex]
        let previousIndex = cornerIndex == range.start ? range.end - 1 : cornerIndex - 1
        let nextIndex = cornerIndex + 1 == range.end ? range.start : cornerIndex + 1
        return .corner(
            ProjectMeshCornerRecord(
                id: source.cornerIDs[cornerIndex],
                faceID: source.faceIDs[faceIndex],
                vertexID: source.cornerVertexIDs[cornerIndex],
                edgeID: source.cornerEdgeIDs[cornerIndex],
                previousID: source.cornerIDs[previousIndex],
                nextID: source.cornerIDs[nextIndex]
            )
        )
    }

    private func referenceUnits(
        domain: ProjectMeshElementDomain,
        index: Int
    ) throws -> Int {
        guard index >= 0, index < count(for: domain) else {
            throw ProjectMeshReadError(
                code: .invalidSource,
                message: "The Mesh element index is outside the source buffer."
            )
        }
        switch domain {
        case .vertex:
            return 1
        case .edge:
            return 3
        case .face:
            let range = source.faceCornerRanges[index]
            return try ProjectMeshReadSupport.checkedAdd(
                1,
                range.count,
                label: "reference"
            )
        case .corner:
            return 6
        }
    }

    private func referenceUnits(
        for key: ElementKey,
        index: SourceIndex
    ) throws -> Int {
        switch key {
        case .vertex(let id):
            guard let elementIndex = index.vertexIndices[id] else {
                throw missingRecord(key)
            }
            return try referenceUnits(domain: .vertex, index: elementIndex)
        case .edge(let id):
            guard let elementIndex = index.edgeIndices[id] else {
                throw missingRecord(key)
            }
            return try referenceUnits(domain: .edge, index: elementIndex)
        case .face(let id):
            guard let elementIndex = index.faceIndices[id] else {
                throw missingRecord(key)
            }
            return try referenceUnits(domain: .face, index: elementIndex)
        case .corner(let id):
            guard let elementIndex = index.cornerIndices[id] else {
                throw missingRecord(key)
            }
            return try referenceUnits(domain: .corner, index: elementIndex)
        }
    }

    private enum ElementKey: Hashable, Sendable {
        case vertex(MeshVertexID)
        case edge(MeshEdgeID)
        case face(MeshFaceID)
        case corner(MeshCornerID)

        init(_ reference: ProjectMeshElementReference) {
            switch reference {
            case .vertex(let id):
                self = .vertex(id)
            case .edge(let id):
                self = .edge(id)
            case .face(let id):
                self = .face(id)
            case .corner(let id):
                self = .corner(id)
            }
        }

        var domain: ProjectMeshElementDomain {
            switch self {
            case .vertex:
                .vertex
            case .edge:
                .edge
            case .face:
                .face
            case .corner:
                .corner
            }
        }

        var numericSortValue: UInt64 {
            switch self {
            case .vertex(let id):
                id.rawValue
            case .edge(let id):
                id.rawValue
            case .face(let id):
                id.rawValue
            case .corner(let id):
                id.rawValue
            }
        }
    }

    private struct SourceIndex: Sendable {
        let vertexIndices: [MeshVertexID: Int]
        let edgeIndices: [MeshEdgeID: Int]
        let faceIndices: [MeshFaceID: Int]
        let cornerIndices: [MeshCornerID: Int]
        let faceIndexByCorner: [Int: Int]
        let adjacency: [ElementKey: Set<ElementKey>]

        func contains(_ reference: ProjectMeshElementReference) -> Bool {
            switch reference {
            case .vertex(let id):
                vertexIndices[id] != nil
            case .edge(let id):
                edgeIndices[id] != nil
            case .face(let id):
                faceIndices[id] != nil
            case .corner(let id):
                cornerIndices[id] != nil
            }
        }
    }

    private func makeSourceIndex(
        budget: inout ProjectMeshReadBudget
    ) throws -> SourceIndex {
        var vertexIndices: [MeshVertexID: Int] = [:]
        var edgeIndices: [MeshEdgeID: Int] = [:]
        var faceIndices: [MeshFaceID: Int] = [:]
        var cornerIndices: [MeshCornerID: Int] = [:]
        var faceIndexByCorner: [Int: Int] = [:]
        var adjacency: [ElementKey: Set<ElementKey>] = [:]
        func connect(_ lhs: ElementKey, _ rhs: ElementKey) {
            adjacency[lhs, default: []].insert(rhs)
            adjacency[rhs, default: []].insert(lhs)
        }

        for index in source.vertexIDs.indices {
            try Task.checkCancellation()
            try budget.consumeScanned(1, label: "vertex index")
            let vertexID = source.vertexIDs[index]
            vertexIndices[vertexID] = index
            adjacency[.vertex(vertexID)] = []
        }
        for index in source.edgeIDs.indices {
            try Task.checkCancellation()
            try budget.consumeScanned(1, label: "edge index")
            let edge = ElementKey.edge(source.edgeIDs[index])
            edgeIndices[source.edgeIDs[index]] = index
            let endpoints = source.edgeEndpoints[index]
            try budget.consumeScanned(2, label: "edge endpoint relation")
            connect(edge, .vertex(endpoints.start))
            connect(edge, .vertex(endpoints.end))
        }
        for faceIndex in source.faceIDs.indices {
            try Task.checkCancellation()
            try budget.consumeScanned(1, label: "face index")
            let face = ElementKey.face(source.faceIDs[faceIndex])
            faceIndices[source.faceIDs[faceIndex]] = faceIndex
            let range = source.faceCornerRanges[faceIndex]
            for cornerIndex in range.start..<range.end {
                try Task.checkCancellation()
                try budget.consumeScanned(1, label: "face corner relation")
                faceIndexByCorner[cornerIndex] = faceIndex
                let corner = ElementKey.corner(source.cornerIDs[cornerIndex])
                try budget.consumeScanned(3, label: "corner relation")
                connect(face, corner)
                connect(corner, .vertex(source.cornerVertexIDs[cornerIndex]))
                connect(corner, .edge(source.cornerEdgeIDs[cornerIndex]))
            }
        }
        for index in source.cornerIDs.indices {
            try Task.checkCancellation()
            try budget.consumeScanned(1, label: "corner index")
            cornerIndices[source.cornerIDs[index]] = index
        }
        return SourceIndex(
            vertexIndices: vertexIndices,
            edgeIndices: edgeIndices,
            faceIndices: faceIndices,
            cornerIndices: cornerIndices,
            faceIndexByCorner: faceIndexByCorner,
            adjacency: adjacency
        )
    }

    private func faceIndex(
        containingCornerAt cornerIndex: Int,
        budget: inout ProjectMeshReadBudget
    ) throws -> Int {
        var lowerBound = 0
        var upperBound = source.faceCornerRanges.count
        while lowerBound < upperBound {
            try Task.checkCancellation()
            try budget.consumeScanned(1, label: "corner face lookup")
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            let range = source.faceCornerRanges[midpoint]
            if cornerIndex < range.start {
                upperBound = midpoint
            } else if cornerIndex >= range.end {
                lowerBound = midpoint + 1
            } else {
                return midpoint
            }
        }
        throw ProjectMeshReadError(
            code: .invalidSource,
            message: "A Mesh corner is not covered by a face range."
        )
    }

    private func missingRecord(_ key: ElementKey) -> ProjectMeshReadError {
        ProjectMeshReadError(
            code: .invalidSource,
            message: "The Mesh source lost an element while building a read response: \(key.numericSortValue)."
        )
    }
}
