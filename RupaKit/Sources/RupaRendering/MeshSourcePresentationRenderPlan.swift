import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene

/// A snapshot-owned, indexed traversal plan for MeshSource presentation.
///
/// Construction world-transforms every vertex of an occurrence exactly once
/// into a derived position buffer and records the occurrence's triangles as
/// checked indices into it, so no consumer re-transforms a corner and no
/// second validating traversal is required. The immutable source buffers are
/// never copied: the plan retains the source vertex-ID buffer for picking
/// provenance and allocates only the transformed positions, the triangle
/// indices, boundary corner indices, and per-triangle face identities. The
/// native adapter derives Float positions, face normals, and boundary indices
/// from that provenance. Their input-buffer costs are admitted here before
/// either plan construction or native preparation allocates them. All such costs are charged
/// against `MeshSourcePresentationPlanLimits` before any storage is reserved
/// or grown.
public struct MeshSourcePresentationRenderPlan: Sendable {
    /// Vertices transformed between two cancellation checks. A cancelled build
    /// stops within one range instead of transforming a whole occurrence.
    private static let vertexCancellationStride = 4_096

    public let snapshotID: EvaluationSnapshotID
    public let projectID: ProjectID
    public let itemCount: Int
    public let positionCount: Int
    public let triangleCount: Int
    /// Number of UInt32 indices in the source-face boundary line buffer.
    /// Boundary pairs are counted twice, once for each endpoint.
    public let boundaryIndexCount: Int
    /// Admitted plan storage plus native-adapter input buffers. RealityKit's
    /// opaque internal allocations are not included in this byte count.
    public let retainedByteCount: Int
    /// Upper-bound admission for retained geometry plus temporary index/face work.
    public let workingByteCount: Int
    /// Caller-validated retained-byte ceiling available to native preparation.
    /// RealityKit's opaque allocations are still count-bounded separately.
    let nativePreparationByteLimit: Int
    public let telemetry: MeshSourcePresentationRenderTelemetry
    let occurrences: [Occurrence]

    /// One occurrence's derived presentation geometry.
    ///
    /// `positions` is index-aligned with `vertexIDs`, so one triangle index
    /// selects both the world position a draw pass projects and the source
    /// vertex identity picking reports.
    struct Occurrence: Sendable {
        let occurrenceID: SceneOccurrenceID
        let definitionID: ObjectDefinitionID
        let representationID: GeometryRepresentationID
        let sourceReference: GeometrySourceReference
        let vertexIDs: GeometryBuffer<MeshVertexID>
        let cornerEdgeIDs: GeometryBuffer<MeshEdgeID>
        let positions: [GeometryPoint3D]
        let faceIDs: [MeshFaceID]
        let vertexIndices: [UInt32]
        let boundaryCornerIndices: [UInt32]
        let boundaryIndexCount: Int

        var triangleCount: Int {
            faceIDs.count
        }

        func triangle(at index: Int) -> MeshSourcePresentationTriangle {
            let base = index * 3
            let first = Int(vertexIndices[base])
            let second = Int(vertexIndices[base + 1])
            let third = Int(vertexIndices[base + 2])
            return MeshSourcePresentationTriangle(
                occurrenceID: occurrenceID,
                definitionID: definitionID,
                representationID: representationID,
                sourceReference: sourceReference,
                faceID: faceIDs[index],
                firstVertexID: vertexIDs[first],
                secondVertexID: vertexIDs[second],
                thirdVertexID: vertexIDs[third],
                firstPosition: positions[first],
                secondPosition: positions[second],
                thirdPosition: positions[third],
                firstEdgeID: edgeID(at: base),
                secondEdgeID: edgeID(at: base + 1),
                thirdEdgeID: edgeID(at: base + 2)
            )
        }

        private func edgeID(at side: Int) -> MeshEdgeID? {
            let corner = boundaryCornerIndices[side]
            return corner == UInt32.max ? nil : cornerEdgeIDs[Int(corner)]
        }
    }

    /// Cumulative derived-resource accounting for one construction.
    private struct Charge {
        private static let indexStride = MemoryLayout<UInt32>.stride
        private static let faceIDStride = MemoryLayout<MeshFaceID>.stride
        private static let positionStride = MemoryLayout<GeometryPoint3D>.stride

        let limits: MeshSourcePresentationPlanLimits
        private(set) var itemCount = 0
        private(set) var positionCount = 0
        private(set) var triangleCount = 0
        private(set) var byteCount = 0
        private(set) var workingByteCount = 0

        mutating func chargeItems(_ count: Int) throws {
            itemCount = try Self.sum(itemCount, count)
            try Self.admit(itemCount, limits.maxItemCount, named: "item")
            // Occurrence records, adapter entry/lookup references, and metadata
            // allowance. Native SDK allocations have a separate count/lifetime
            // contract; this is not a byte estimate of its opaque allocator.
            try chargeBytes(try Self.product(count, MemoryLayout<Occurrence>.stride + 128))
        }

        mutating func chargePositions(_ count: Int) throws {
            positionCount = try Self.sum(positionCount, count)
            try Self.admit(
                positionCount,
                limits.maxPositionCount,
                named: "transformed position"
            )
            try chargeBytes(try Self.product(
                count,
                Self.positionStride + MemoryLayout<MeshVertexID>.stride + MemoryLayout<SIMD3<Float>>.stride
            ))
        }

        mutating func chargeTriangles(_ count: Int) throws {
            triangleCount = try Self.sum(triangleCount, count)
            try Self.admit(triangleCount, limits.maxTriangleCount, named: "triangle")
            let indexBytes = try Self.product(
                try Self.product(count, 3),
                Self.indexStride
            )
            let faceBytes = try Self.product(count, Self.faceIDStride)
            // Plan vertex indices and corner provenance remain CPU-owned.
            // Native preparation additionally owns one Float normal per face;
            // face-rate expansion inside MeshResource is SDK-owned, not ours.
            let normalBytes = try Self.product(count, MemoryLayout<SIMD3<Float>>.stride)
            // Collision-only input has original and reversed winding (6 indices
            // per source triangle); visual topology remains unchanged.
            try chargeBytes(try Self.sum(try Self.sum(try Self.product(indexBytes, 4), faceBytes), normalBytes))
        }

        mutating func chargeBoundaryIndices(_ count: Int) throws {
            let indexBytes = try Self.product(count, Self.indexStride)
            // Native preparation derives this input array off MainActor before
            // the SDK-required scoped LowLevelMesh upload. Charging every
            // occurrence is conservative even though preparation is sequential.
            try chargeBytes(indexBytes)
        }

        mutating func admitScratch(_ bytes: Int) throws {
            let total = try Self.sum(byteCount, bytes)
            try Self.admit(total, limits.maxRetainedByteCount, named: "working byte")
            workingByteCount = max(workingByteCount, total)
        }

        private mutating func chargeBytes(_ count: Int) throws {
            byteCount = try Self.sum(byteCount, count)
            try Self.admit(byteCount, limits.maxRetainedByteCount, named: "retained byte")
            workingByteCount = max(workingByteCount, byteCount)
        }

        private static func admit(_ used: Int, _ limit: Int, named name: String) throws {
            guard used <= limit else {
                throw MeshSourcePresentationRenderError(
                    code: .resourceExhausted,
                    message: """
                        Presentation plan \(name) count \(used) exceeds its limit \(limit).
                        """
                )
            }
        }

        static func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
            let result = lhs.addingReportingOverflow(rhs)
            guard !result.overflow else {
                throw MeshSourcePresentationRenderError(
                    code: .sizeOverflow,
                    message: "Presentation plan resource count exceeds the supported range."
                )
            }
            return result.partialValue
        }

        static func product(_ lhs: Int, _ rhs: Int) throws -> Int {
            let result = lhs.multipliedReportingOverflow(by: rhs)
            guard !result.overflow else {
                throw MeshSourcePresentationRenderError(
                    code: .sizeOverflow,
                    message: "Presentation plan resource count exceeds the supported range."
                )
            }
            return result.partialValue
        }
    }

    private struct BuiltOccurrence {
        let occurrence: Occurrence
        let telemetry: MeshTriangulationTelemetry
    }

    public init(
        scene: UniversalViewportScene,
        tolerance: Double = 1e-9,
        limits: MeshTriangulationLimits = .standard,
        planLimits: MeshSourcePresentationPlanLimits = .standard
    ) throws {
        try Task.checkCancellation()
        try planLimits.validate()
        self.nativePreparationByteLimit = planLimits.maxRetainedByteCount
        do {
            try limits.validate()
        } catch {
            throw Self.triangulationError(error)
        }
        var charge = Charge(limits: planLimits)
        try charge.chargeItems(scene.items.count)
        var occurrences: [Occurrence] = []
        occurrences.reserveCapacity(scene.items.count)
        var telemetry = MeshSourcePresentationRenderTelemetry()
        for item in scene.items {
            try Task.checkCancellation()
            let built = try Self.makeOccurrence(
                item: item,
                tolerance: tolerance,
                limits: limits,
                charge: &charge
            )
            telemetry = try telemetry.adding(
                MeshSourcePresentationRenderTelemetry(built.telemetry)
            )
            occurrences.append(built.occurrence)
        }
        self.snapshotID = scene.snapshotID
        self.projectID = scene.projectID
        self.itemCount = occurrences.count
        self.positionCount = charge.positionCount
        self.triangleCount = charge.triangleCount
        var boundaryIndexCount = 0
        for occurrence in occurrences {
            boundaryIndexCount = try Charge.sum(
                boundaryIndexCount,
                occurrence.boundaryIndexCount
            )
        }
        self.boundaryIndexCount = boundaryIndexCount
        self.retainedByteCount = charge.byteCount
        self.workingByteCount = charge.workingByteCount
        self.telemetry = telemetry
        self.occurrences = occurrences
        try Task.checkCancellation()
    }

    /// Traverses the plan's world-space triangles.
    ///
    /// Construction validated every source range, transform, position, and
    /// index, so traversal cannot fail; this rethrows only what the consumer's
    /// own closure throws.
    public func forEachTriangle(
        _ visit: (MeshSourcePresentationTriangle) throws -> Void
    ) rethrows {
        for occurrence in occurrences {
            for index in 0..<occurrence.triangleCount {
                try visit(occurrence.triangle(at: index))
            }
        }
    }

    /// Traverses the plan one occurrence at a time, so a consumer can work in
    /// the plan's retained shape: one world position per source vertex, indexed
    /// per triangle. Construction validated every index, so traversal cannot
    /// fail; this rethrows only what the consumer's own closure throws.
    public func forEachOccurrence(
        _ visit: (MeshSourcePresentationOccurrenceView) throws -> Void
    ) rethrows {
        for occurrence in occurrences {
            try visit(MeshSourcePresentationOccurrenceView(occurrence: occurrence))
        }
    }

    private static func makeOccurrence(
        item: UniversalViewportSceneItem,
        tolerance: Double,
        limits: MeshTriangulationLimits,
        charge: inout Charge
    ) throws -> BuiltOccurrence {
        do {
            try item.validate()
        } catch let error as UniversalViewportSceneError {
            throw sceneItemError(error)
        }

        guard item.worldTransform.values.count == 16,
              item.worldTransform.values.allSatisfy(\.isFinite) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidTransform,
                message: "Presentation item \(item.occurrenceID.rawValue) has an invalid world transform."
            )
        }

        let mesh = item.mesh
        guard mesh.vertexIDs.count == mesh.vertexPositions.count else {
            throw MeshSourcePresentationRenderError(
                code: .invalidVertexReference,
                message: "Presentation MeshSource vertex IDs and positions have different counts."
            )
        }
        guard mesh.faceIDs.count == mesh.faceCornerRanges.count else {
            throw MeshSourcePresentationRenderError(
                code: .invalidFaceRange,
                message: "Presentation MeshSource face IDs and corner ranges have different counts."
            )
        }
        guard mesh.cornerIDs.count == mesh.cornerVertexIDs.count,
              mesh.cornerIDs.count == mesh.cornerEdgeIDs.count,
              mesh.cornerIDs.count < Int(UInt32.max) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidCornerReference,
                message: "Presentation MeshSource corner references have invalid counts."
            )
        }

        let vertexCount = mesh.vertexIDs.count
        try charge.chargePositions(vertexCount)
        var triangleCount = 0
        var maximumFaceCorners = 0
        for range in mesh.faceCornerRanges {
            try Task.checkCancellation()
            guard range.count >= 3 else {
                throw MeshSourcePresentationRenderError(
                    code: .degenerateFace, message: "A face requires at least three corners."
                )
            }
            guard range.count <= limits.maxFaceCornerCount else {
                throw MeshSourcePresentationRenderError(
                    code: .budgetExceeded,
                    message: "Mesh face corner count exceeds the triangulation limit."
                )
            }
            triangleCount = try Charge.sum(triangleCount, range.count - 2)
            maximumFaceCorners = max(maximumFaceCorners, range.count)
        }
        try charge.chargeTriangles(triangleCount)
        // Every triangulated triangle has at most three source-face boundary
        // sides. The checked upper bound admits the derived GPU line indices
        // before any boundary storage is reserved or filled.
        try charge.chargeBoundaryIndices(try Charge.product(triangleCount, 6))

        let triangulationIndex: MeshSourceTriangulationIndex
        do {
            let indexBytes = try MeshSourceTriangulationIndex.storageReservation(vertexCount: vertexCount)
            // Face triangulation is bounded by Geometry's corner ceiling. This
            // reserves its points, IDs, triangles and ear-clipping work arrays.
            let faceBytes = try Charge.product(maximumFaceCorners, 256)
            let boundaryLookupBytes = try MeshSourceTriangulationIndex.storageReservation(vertexCount: maximumFaceCorners)
            try charge.admitScratch(try Charge.sum(indexBytes, try Charge.sum(faceBytes, boundaryLookupBytes)))
            triangulationIndex = try mesh.makeTriangulationIndex()
        } catch let error as MeshTriangulationError {
            throw triangulationError(error)
        }

        let positions = try transformedPositions(
            of: mesh,
            by: item.worldTransform,
            vertexCount: vertexCount
        )

        var faceIDs: [MeshFaceID] = []
        var vertexIndices: [UInt32] = []
        var boundaryCornerIndices: [UInt32] = []
        var boundaryIndexCount = 0
        faceIDs.reserveCapacity(triangleCount)
        vertexIndices.reserveCapacity(try Charge.product(triangleCount, 3))
        boundaryCornerIndices.reserveCapacity(try Charge.product(triangleCount, 3))
        var triangulationTelemetry = MeshTriangulationTelemetry()
        for faceIndex in mesh.faceCornerRanges.indices {
            try Task.checkCancellation()
            let faceTriangles: [MeshTriangle]
            do {
                faceTriangles = try mesh.triangulate(
                    faceIndex: faceIndex,
                    using: triangulationIndex,
                    tolerance: tolerance,
                    limits: limits,
                    telemetry: &triangulationTelemetry
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as MeshTriangulationError {
                throw triangulationError(error)
            } catch {
                throw MeshSourcePresentationRenderError(
                    code: .failed,
                    message: String(describing: error)
                )
            }
            guard faceTriangles.count == mesh.faceCornerRanges[faceIndex].count - 2 else {
                throw MeshSourcePresentationRenderError(
                    code: .failed, message: "Triangulation did not match its admitted triangle count."
                )
            }
            let range = mesh.faceCornerRanges[faceIndex]
            var cornerByVertex: [MeshVertexID: Int] = [:]
            cornerByVertex.reserveCapacity(range.count)
            for corner in range.start..<range.end {
                cornerByVertex[mesh.cornerVertexIDs[corner]] = corner
            }
            func boundaryCorner(_ a: MeshVertexID, _ b: MeshVertexID) throws -> UInt32 {
                guard let first = cornerByVertex[a], let second = cornerByVertex[b] else {
                    throw MeshSourcePresentationRenderError(
                        code: .invalidVertexReference,
                        message: "A presentation triangle references a vertex outside its source face."
                    )
                }
                if (first + 1 == range.end ? range.start : first + 1) == second { return UInt32(first) }
                if (second + 1 == range.end ? range.start : second + 1) == first { return UInt32(second) }
                return UInt32.max
            }
            for triangle in faceTriangles {
                faceIDs.append(triangle.faceID)
                let firstBoundary = try boundaryCorner(triangle.vertexIDs.0, triangle.vertexIDs.1)
                let secondBoundary = try boundaryCorner(triangle.vertexIDs.1, triangle.vertexIDs.2)
                let thirdBoundary = try boundaryCorner(triangle.vertexIDs.2, triangle.vertexIDs.0)
                boundaryCornerIndices.append(firstBoundary)
                boundaryCornerIndices.append(secondBoundary)
                boundaryCornerIndices.append(thirdBoundary)
                if firstBoundary != UInt32.max {
                    boundaryIndexCount = try Charge.sum(boundaryIndexCount, 2)
                }
                if secondBoundary != UInt32.max {
                    boundaryIndexCount = try Charge.sum(boundaryIndexCount, 2)
                }
                if thirdBoundary != UInt32.max {
                    boundaryIndexCount = try Charge.sum(boundaryIndexCount, 2)
                }
                vertexIndices.append(
                    try positionIndex(
                        for: triangle.vertexIDs.0,
                        in: triangulationIndex,
                        vertexCount: vertexCount
                    )
                )
                vertexIndices.append(
                    try positionIndex(
                        for: triangle.vertexIDs.1,
                        in: triangulationIndex,
                        vertexCount: vertexCount
                    )
                )
                vertexIndices.append(
                    try positionIndex(
                        for: triangle.vertexIDs.2,
                        in: triangulationIndex,
                        vertexCount: vertexCount
                    )
                )
            }
        }

        let occurrence = Occurrence(
            occurrenceID: item.occurrenceID,
            definitionID: item.definitionID,
            representationID: item.representationID,
            sourceReference: item.sourceReference,
            vertexIDs: mesh.vertexIDs,
            cornerEdgeIDs: mesh.cornerEdgeIDs,
            positions: positions,
            faceIDs: faceIDs,
            vertexIndices: vertexIndices,
            boundaryCornerIndices: boundaryCornerIndices,
            boundaryIndexCount: boundaryIndexCount
        )
        return BuiltOccurrence(
            occurrence: occurrence,
            telemetry: triangulationTelemetry
        )
    }

    private static func transformedPositions(
        of mesh: MeshSource,
        by worldTransform: GeometryTransform3D,
        vertexCount: Int
    ) throws -> [GeometryPoint3D] {
        var positions: [GeometryPoint3D] = []
        positions.reserveCapacity(vertexCount)
        var rangeStart = 0
        while rangeStart < vertexCount {
            try Task.checkCancellation()
            let rangeEnd = min(rangeStart + vertexCancellationStride, vertexCount)
            for index in rangeStart..<rangeEnd {
                positions.append(
                    try transformed(mesh.vertexPositions[index], by: worldTransform)
                )
            }
            rangeStart = rangeEnd
        }
        return positions
    }

    private static func positionIndex(
        for vertexID: MeshVertexID,
        in triangulationIndex: MeshSourceTriangulationIndex,
        vertexCount: Int
    ) throws -> UInt32 {
        guard let index = triangulationIndex.positionIndex(for: vertexID),
              index >= 0,
              index < vertexCount,
              index <= Int(UInt32.max) else {
            throw MeshSourcePresentationRenderError(
                code: .invalidVertexReference,
                message: "Presentation MeshSource vertex reference is outside its position buffer."
            )
        }
        return UInt32(index)
    }

    private static func transformed(
        _ point: GeometryPoint3D,
        by worldTransform: GeometryTransform3D
    ) throws -> GeometryPoint3D {
        do {
            return try worldTransform.applying(to: point)
        } catch let error as MeshSourceError {
            throw MeshSourcePresentationRenderError(
                code: .transformFailure,
                message: error.message
            )
        } catch {
            throw MeshSourcePresentationRenderError(
                code: .transformFailure,
                message: String(describing: error)
            )
        }
    }

    private static func sceneItemError(
        _ error: UniversalViewportSceneError
    ) -> MeshSourcePresentationRenderError {
        let code: MeshSourcePresentationRenderError.Code
        switch error.code {
        case .invalidIdentifier:
            code = .invalidIdentifier
        case .sourceMismatch, .sourceIdentityMismatch:
            code = .sourceAuthorityMismatch
        case .missingDefinition, .projectMismatch, .purposeMismatch, .occurrenceMismatch:
            code = .invalidSceneItem
        }
        return MeshSourcePresentationRenderError(code: code, message: error.message)
    }

    private static func triangulationError(
        _ error: MeshTriangulationError
    ) -> MeshSourcePresentationRenderError {
        let code: MeshSourcePresentationRenderError.Code
        switch error.code {
        case .missingFace:
            code = .missingFace
        case .invalidFaceRange:
            code = .invalidFaceRange
        case .degenerateFace:
            code = .degenerateFace
        case .nonPlanar:
            code = .nonPlanar
        case .degenerate:
            code = .degenerate
        case .failed:
            code = .failed
        case .invalidReference:
            code = .invalidVertexReference
        case .invalidLimits:
            code = .failed
        case .budgetExceeded:
            code = .budgetExceeded
        case .sizeOverflow:
            code = .sizeOverflow
        }
        return MeshSourcePresentationRenderError(code: code, message: error.message)
    }
}
