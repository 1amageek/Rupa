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
/// indices, and the per-triangle face identity. That derived cost is charged
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
    /// Bytes of derived storage the plan holds, as charged during construction.
    public let retainedByteCount: Int
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
        let positions: [GeometryPoint3D]
        let faceIDs: [MeshFaceID]
        let vertexIndices: [UInt32]

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
                thirdPosition: positions[third]
            )
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

        mutating func chargeItems(_ count: Int) throws {
            itemCount = try Self.sum(itemCount, count)
            try Self.admit(itemCount, limits.maxItemCount, named: "item")
        }

        mutating func chargePositions(_ count: Int) throws {
            positionCount = try Self.sum(positionCount, count)
            try Self.admit(
                positionCount,
                limits.maxPositionCount,
                named: "transformed position"
            )
            try chargeBytes(try Self.product(count, Self.positionStride))
        }

        mutating func chargeTriangles(_ count: Int) throws {
            triangleCount = try Self.sum(triangleCount, count)
            try Self.admit(triangleCount, limits.maxTriangleCount, named: "triangle")
            let indexBytes = try Self.product(
                try Self.product(count, 3),
                Self.indexStride
            )
            let faceBytes = try Self.product(count, Self.faceIDStride)
            try chargeBytes(try Self.sum(indexBytes, faceBytes))
        }

        private mutating func chargeBytes(_ count: Int) throws {
            byteCount = try Self.sum(byteCount, count)
            try Self.admit(byteCount, limits.maxRetainedByteCount, named: "retained byte")
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

        private static func sum(_ lhs: Int, _ rhs: Int) throws -> Int {
            let result = lhs.addingReportingOverflow(rhs)
            guard !result.overflow else {
                throw MeshSourcePresentationRenderError(
                    code: .sizeOverflow,
                    message: "Presentation plan resource count exceeds the supported range."
                )
            }
            return result.partialValue
        }

        private static func product(_ lhs: Int, _ rhs: Int) throws -> Int {
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
        try planLimits.validate()
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
        self.retainedByteCount = charge.byteCount
        self.telemetry = telemetry
        self.occurrences = occurrences
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
        guard mesh.cornerIDs.count == mesh.cornerVertexIDs.count else {
            throw MeshSourcePresentationRenderError(
                code: .invalidCornerReference,
                message: "Presentation MeshSource corner IDs and vertex references have different counts."
            )
        }

        let triangulationIndex: MeshSourceTriangulationIndex
        do {
            triangulationIndex = try mesh.makeTriangulationIndex()
        } catch let error as MeshTriangulationError {
            throw triangulationError(error)
        }

        let vertexCount = mesh.vertexIDs.count
        try charge.chargePositions(vertexCount)
        let positions = try transformedPositions(
            of: mesh,
            by: item.worldTransform,
            vertexCount: vertexCount
        )

        var faceIDs: [MeshFaceID] = []
        var vertexIndices: [UInt32] = []
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
            } catch let error as MeshTriangulationError {
                throw triangulationError(error)
            } catch {
                throw MeshSourcePresentationRenderError(
                    code: .failed,
                    message: String(describing: error)
                )
            }
            try charge.chargeTriangles(faceTriangles.count)
            for triangle in faceTriangles {
                faceIDs.append(triangle.faceID)
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
            positions: positions,
            faceIDs: faceIDs,
            vertexIndices: vertexIndices
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
