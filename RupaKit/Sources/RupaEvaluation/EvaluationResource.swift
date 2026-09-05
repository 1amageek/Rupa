import RupaGeometry

/// A dimension one project evaluation is bounded in.
///
/// The dimensions are provider-neutral: an authored mesh and a CAD body are
/// charged against the same ceilings, so a product policy bounds an evaluation
/// without knowing which provider produced its geometry. Edges are storage the
/// `byteCount` dimension accounts for rather than a dimension of their own,
/// because no product policy bounds them independently of the faces they belong
/// to.
public enum EvaluationResource: String, Codable, Sendable, Hashable, CaseIterable {
    case sourceCount
    case vertexCount
    case faceCount
    case cornerCount
    case triangleCount
    case byteCount
}

extension MeshResourceUsage {
    /// What one materialized mesh accounts for in `resource`.
    ///
    /// A mesh belongs to exactly one geometry source, so it accounts for one
    /// `sourceCount`. This is the single projection of a mesh onto the
    /// evaluation dimensions, so a charge and the failure it reports cannot
    /// disagree about which amount was requested.
    public func amount(for resource: EvaluationResource) -> Int {
        switch resource {
        case .sourceCount: 1
        case .vertexCount: vertexCount
        case .faceCount: faceCount
        case .cornerCount: cornerCount
        case .triangleCount: triangleCount
        case .byteCount: byteCount
        }
    }
}
