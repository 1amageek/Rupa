import RupaEvaluation
import RupaCoreTypes
import RupaGeometry
import SwiftCAD

/// The cumulative tessellation one provider call is admitted to return.
///
/// The kernel charges only what one invocation tessellated, and
/// `DocumentEvaluationEngine` may carry unchanged bodies forward from a prior
/// evaluation, so a reused body may not consume a new kernel tessellation
/// invocation. This admission is charged by the provider for every mesh it
/// actually returns, cached or freshly evaluated, so a request is refused by
/// the same ceilings whichever path produced the mesh.
struct CADTessellationAdmission {
    /// The ceilings a single kernel invocation of this request is admitted under.
    private let initialLimits: TessellationLimits
    private let allowance: EvaluationAllowance
    private var used: TessellationUsage = .zero
    private var usedUniversal: MeshResourceUsage = .zero

    /// The kernel ceilings lowered to what `allowance` still admits.
    ///
    /// The element dimensions map one to one: one kernel vertex is one universal
    /// vertex, one emitted index is one universal corner, and one emitted
    /// triangle is one universal face, so a refusal in those dimensions is
    /// exact. Bytes do not map one to one: `allowance.byteCount` counts the
    /// universal `MeshSource` footprint, which is several times the kernel's
    /// position, normal and index arrays, so lowering the kernel byte ceiling to
    /// it only ever narrows and never refuses earlier than the universal
    /// footprint would. The engine's charge of the returned `MeshResourceUsage`
    /// remains the authority on bytes.
    ///
    /// - Throws: `CADIntegrationError` with `resourceExhausted` when a dimension
    ///   of `allowance` admits nothing. An exhausted remainder is a state the
    ///   engine reaches, while `TessellationLimits` must admit something, so the
    ///   refusal is reported here rather than as an invalid limit.
    init(allowance: EvaluationAllowance) throws {
        guard allowance.vertexCount > 0,
              allowance.faceCount > 0,
              allowance.cornerCount > 0,
              allowance.triangleCount > 0,
              allowance.byteCount > 0 else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "The evaluation allowance admits no further CAD geometry: "
                    + "\(allowance.vertexCount) vertices, \(allowance.faceCount) faces, "
                    + "\(allowance.cornerCount) corners, "
                    + "\(allowance.triangleCount) triangles, \(allowance.byteCount) bytes remain."
            )
        }
        self.allowance = allowance
        let maximumTriangleCount = min(allowance.faceCount, allowance.triangleCount)
        initialLimits = TessellationLimits.standard.lowered(
            to: TessellationLimits(
                maximumVertexCount: allowance.vertexCount,
                maximumIndexCount: allowance.cornerCount,
                maximumTriangleCount: maximumTriangleCount,
                maximumByteCount: allowance.byteCount
            )
        )
    }

    /// Charges `mesh` against this call's remaining admission.
    ///
    /// - Throws: `CADIntegrationError` with `resourceExhausted` when the
    ///   cumulative total this call would return exceeds the admitted ceilings.
    mutating func admit(_ mesh: Mesh) throws -> MeshResourceUsage {
        let total = try charging(mesh)
        if let exceeded = total.firstResourceExceeding(initialLimits) {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD evaluation would return \(total.amount(for: exceeded)) "
                    + "\(exceeded.rawValue) for this request, but only "
                    + "\(initialLimits.limit(for: exceeded)) is admitted."
            )
        }

        let universal = try universalUsage(for: mesh)
        let universalTotal: MeshResourceUsage
        do {
            universalTotal = try usedUniversal.adding(universal)
        } catch {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "Universal CAD mesh resource usage is not representable: \(error)"
            )
        }
        if let exceeded = firstResourceExceeded(universalTotal) {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD evaluation would materialize \(universalTotal.amount(for: exceeded)) "
                    + "\(exceeded.rawValue) for this request, but only "
                    + "\(allowance.amount(for: exceeded)) is admitted."
            )
        }
        used = total
        usedUniversal = universalTotal
        return universal
    }

    /// Returns the kernel ceiling remaining before the next fresh source evaluation.
    ///
    /// Kernel limits are per evaluator invocation, while this admission spans all
    /// sources in one provider request. The returned ceiling therefore subtracts
    /// every earlier kernel charge before it reaches another evaluator. An
    /// exhausted dimension is refused here so the evaluator never constructs a
    /// mesh with an invalid zero limit.
    func limitsForNextSource() throws -> TessellationLimits {
        let remainingByteCount = min(
            try remaining(
                initialLimits.maximumByteCount,
                used.byteCount,
                resource: .byteCount
            ),
            try remaining(
                allowance.byteCount,
                usedUniversal.byteCount,
                resource: .byteCount
            )
        )
        let limits = TessellationLimits(
            maximumVertexCount: try remaining(
                initialLimits.maximumVertexCount,
                used.vertexCount,
                resource: .vertexCount
            ),
            maximumIndexCount: try remaining(
                initialLimits.maximumIndexCount,
                used.indexCount,
                resource: .indexCount
            ),
            maximumTriangleCount: try remaining(
                initialLimits.maximumTriangleCount,
                used.triangleCount,
                resource: .triangleCount
            ),
            maximumByteCount: remainingByteCount
        )
        return limits
    }

    /// Verifies that the source materializer emitted exactly what admission reserved.
    /// This catches a conversion-path drift before the cache can retain the source.
    func verify(
        actual: MeshResourceUsage,
        predicted: MeshResourceUsage
    ) throws {
        guard actual == predicted else {
            throw CADIntegrationError(
                code: .invalidMesh,
                message: "CAD mesh materialization did not match its admitted universal storage footprint."
            )
        }
    }

    private func firstResourceExceeded(
        _ usage: MeshResourceUsage
    ) -> EvaluationResource? {
        if usage.vertexCount > allowance.vertexCount { return .vertexCount }
        if usage.faceCount > allowance.faceCount { return .faceCount }
        if usage.cornerCount > allowance.cornerCount { return .cornerCount }
        if usage.triangleCount > allowance.triangleCount { return .triangleCount }
        if usage.byteCount > allowance.byteCount { return .byteCount }
        return nil
    }

    private func remaining(
        _ allowance: Int,
        _ used: Int,
        resource: TessellationResource
    ) throws -> Int {
        guard used <= allowance else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD evaluation already exceeded the remaining \(resource.rawValue) allowance."
            )
        }
        let value = allowance - used
        guard value > 0 else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD evaluation has no remaining \(resource.rawValue) allowance."
            )
        }
        return value
    }

    private func universalUsage(for mesh: Mesh) throws -> MeshResourceUsage {
        guard mesh.indices.count.isMultiple(of: 3) else {
            throw CADIntegrationError(
                code: .invalidMesh,
                message: "CAD mesh index count must be divisible by three."
            )
        }

        let cornerCount = mesh.indices.count
        let faceCount = cornerCount / 3
        var attributeByteCount = 0
        for (count, stride) in [
            (mesh.normals.count, MemoryLayout<GeometryPoint3D>.stride),
            (mesh.textureCoordinates.count, MemoryLayout<GeometryVector2D>.stride),
            (mesh.vertexColors.count, MemoryLayout<GeometryVector4D>.stride),
        ] {
            let bytes = count.multipliedReportingOverflow(by: stride)
            guard !bytes.overflow else {
                throw CADIntegrationError(
                    code: .resourceExhausted,
                    message: "CAD mesh attribute storage is not representable."
                )
            }
            let total = attributeByteCount.addingReportingOverflow(bytes.partialValue)
            guard !total.overflow else {
                throw CADIntegrationError(
                    code: .resourceExhausted,
                    message: "CAD mesh attribute storage is not representable."
                )
            }
            attributeByteCount = total.partialValue
        }

        let baseUsage: MeshResourceUsage
        do {
            baseUsage = try MeshResourceUsage.materializedStorage(
                vertexCount: mesh.positions.count,
                edgeCount: 0,
                faceCount: faceCount,
                cornerCount: cornerCount,
                triangleCount: faceCount,
                attributeByteCount: attributeByteCount
            )
        } catch {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD mesh universal storage is not representable: \(error)"
            )
        }

        let maximumEdgeCount = try maximumAdmittedEdgeCount(for: baseUsage)
        let edgeCount = try uniqueEdgeCount(
            in: mesh.indices,
            maximumCount: maximumEdgeCount
        )
        return try MeshResourceUsage.materializedStorage(
            vertexCount: mesh.positions.count,
            edgeCount: edgeCount,
            faceCount: faceCount,
            cornerCount: cornerCount,
            triangleCount: faceCount,
            attributeByteCount: attributeByteCount
        )
    }

    private func maximumAdmittedEdgeCount(
        for baseUsage: MeshResourceUsage
    ) throws -> Int {
        let total: MeshResourceUsage
        do {
            total = try usedUniversal.adding(baseUsage)
        } catch {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "Universal CAD mesh resource usage is not representable: \(error)"
            )
        }
        if let exceeded = firstResourceExceeded(total) {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD evaluation would materialize \(total.amount(for: exceeded)) "
                    + "\(exceeded.rawValue) for this request, but only "
                    + "\(allowance.amount(for: exceeded)) is admitted."
            )
        }

        let edgeByteStride = MemoryLayout<MeshEdgeID>.stride
            .addingReportingOverflow(MemoryLayout<MeshEdgeEndpoints>.stride)
        guard !edgeByteStride.overflow,
              edgeByteStride.partialValue > 0 else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "Universal CAD edge storage stride is not representable."
            )
        }
        let remainingBytes = allowance.byteCount - total.byteCount
        return remainingBytes / edgeByteStride.partialValue
    }

    private func uniqueEdgeCount(
        in indices: [UInt32],
        maximumCount: Int
    ) throws -> Int {
        try Task.checkCancellation()
        guard maximumCount > 0 else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "Universal CAD edge storage exceeds the remaining byte allowance."
            )
        }
        var keys = Set<UInt64>()
        // Never reserve from the raw index count when the remaining universal
        // byte allowance admits fewer edges. The allowance-derived bound keeps
        // this scratch from becoming an uncharged second topology allocation.
        keys.reserveCapacity(min(indices.count, maximumCount))
        var start = 0
        var triangle = 0
        while start < indices.count {
            if triangle.isMultiple(of: 1_024) {
                try Task.checkCancellation()
            }
            let first = indices[start]
            let second = indices[start + 1]
            let third = indices[start + 2]
            try insertEdge(
                edgeKey(first, second),
                into: &keys,
                maximumCount: maximumCount
            )
            try insertEdge(
                edgeKey(second, third),
                into: &keys,
                maximumCount: maximumCount
            )
            try insertEdge(
                edgeKey(third, first),
                into: &keys,
                maximumCount: maximumCount
            )
            start += 3
            triangle += 1
        }
        return keys.count
    }

    private func insertEdge(
        _ key: UInt64,
        into keys: inout Set<UInt64>,
        maximumCount: Int
    ) throws {
        guard keys.contains(key) || keys.count < maximumCount else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "Universal CAD edge storage exceeds the remaining byte allowance."
            )
        }
        keys.insert(key)
    }

    private func edgeKey(_ first: UInt32, _ second: UInt32) -> UInt64 {
        let low = min(first, second)
        let high = max(first, second)
        return UInt64(low) << 32 | UInt64(high)
    }

    private func charging(_ mesh: Mesh) throws -> TessellationUsage {
        let meshUsage: TessellationUsage
        do {
            meshUsage = try TessellationUsage(mesh: mesh)
        } catch {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD body mesh resource usage is not representable: \(error)"
            )
        }
        return TessellationUsage(
            vertexCount: try sum(used.vertexCount, meshUsage.vertexCount, .vertexCount),
            indexCount: try sum(used.indexCount, meshUsage.indexCount, .indexCount),
            triangleCount: try sum(
                used.triangleCount,
                meshUsage.triangleCount,
                .triangleCount
            ),
            byteCount: try sum(used.byteCount, meshUsage.byteCount, .byteCount)
        )
    }

    private func sum(
        _ lhs: Int,
        _ rhs: Int,
        _ resource: TessellationResource
    ) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD evaluation \(resource.rawValue) for this request is not "
                    + "representable, so it cannot be admitted."
            )
        }
        return result.partialValue
    }
}
