import RupaEvaluation
import SwiftCAD

/// The cumulative tessellation one provider call is admitted to return.
///
/// The kernel charges only what one invocation tessellated, and
/// `DocumentEvaluationEngine` carries unchanged bodies forward from a prior
/// evaluation without consulting the limits, so an exact-revision cache hit can
/// return geometry the kernel never admitted. This admission is charged by the
/// provider for every mesh it actually returns, cached or freshly evaluated, so
/// a request is refused by the same ceilings whichever path produced the mesh.
struct CADTessellationAdmission {
    /// The ceilings a single kernel invocation of this request is admitted under.
    let limits: TessellationLimits
    private var used: TessellationUsage = .zero

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
              allowance.cornerCount > 0,
              allowance.triangleCount > 0,
              allowance.byteCount > 0 else {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "The evaluation allowance admits no further CAD geometry: "
                    + "\(allowance.vertexCount) vertices, \(allowance.cornerCount) corners, "
                    + "\(allowance.triangleCount) triangles, \(allowance.byteCount) bytes remain."
            )
        }
        limits = TessellationLimits.standard.lowered(
            to: TessellationLimits(
                maximumVertexCount: allowance.vertexCount,
                maximumIndexCount: allowance.cornerCount,
                maximumTriangleCount: allowance.triangleCount,
                maximumByteCount: allowance.byteCount
            )
        )
    }

    /// Charges `mesh` against this call's remaining admission.
    ///
    /// - Throws: `CADIntegrationError` with `resourceExhausted` when the
    ///   cumulative total this call would return exceeds the admitted ceilings.
    mutating func admit(_ mesh: Mesh) throws {
        let total = try charging(mesh)
        if let exceeded = total.firstResourceExceeding(limits) {
            throw CADIntegrationError(
                code: .resourceExhausted,
                message: "CAD evaluation would return \(total.amount(for: exceeded)) "
                    + "\(exceeded.rawValue) for this request, but only "
                    + "\(limits.limit(for: exceeded)) is admitted."
            )
        }
        used = total
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
