import RupaGeometry

/// What one evaluation may still charge in every bounded dimension.
///
/// An allowance is distinct from `EvaluationResourceLimits` because a limit must
/// admit something and a remainder must be able to admit nothing: a ceiling of
/// zero is invalid, while an exhausted dimension is a state the engine reaches
/// and a provider must be able to observe before it allocates.
public struct EvaluationAllowance: Equatable, Hashable, Sendable {
    public var sourceCount: Int
    public var vertexCount: Int
    public var faceCount: Int
    public var cornerCount: Int
    public var triangleCount: Int
    public var byteCount: Int

    public init(
        sourceCount: Int,
        vertexCount: Int,
        faceCount: Int,
        cornerCount: Int,
        triangleCount: Int,
        byteCount: Int
    ) {
        self.sourceCount = sourceCount
        self.vertexCount = vertexCount
        self.faceCount = faceCount
        self.cornerCount = cornerCount
        self.triangleCount = triangleCount
        self.byteCount = byteCount
    }

    /// The full allowance a fresh evaluation under `limits` starts with.
    public init(_ limits: EvaluationResourceLimits) {
        self.init(
            sourceCount: limits.maximumSourceCount,
            vertexCount: limits.maximumVertexCount,
            faceCount: limits.maximumFaceCount,
            cornerCount: limits.maximumCornerCount,
            triangleCount: limits.maximumTriangleCount,
            byteCount: limits.maximumByteCount
        )
    }

    public static let exhausted = EvaluationAllowance(
        sourceCount: 0,
        vertexCount: 0,
        faceCount: 0,
        cornerCount: 0,
        triangleCount: 0,
        byteCount: 0
    )

    public func amount(for resource: EvaluationResource) -> Int {
        switch resource {
        case .sourceCount: sourceCount
        case .vertexCount: vertexCount
        case .faceCount: faceCount
        case .cornerCount: cornerCount
        case .triangleCount: triangleCount
        case .byteCount: byteCount
        }
    }

    /// Rejects a remainder no charge could have produced.
    public func validate() throws {
        for resource in EvaluationResource.allCases {
            let value = amount(for: resource)
            guard value >= 0 else {
                throw EvaluationError(
                    code: .invalidLimit,
                    message: "Evaluation allowance \(resource.rawValue) cannot be negative, "
                        + "but is \(value)."
                )
            }
        }
    }

    /// The first dimension this allowance does not admit `usage` in, in
    /// declaration order, or `nil` when every dimension admits it.
    ///
    /// `sourceCount` is not compared, because one mesh is charged against the
    /// element dimensions while the source it belongs to is charged separately.
    public func firstResourceExceeded(
        by usage: MeshResourceUsage
    ) -> EvaluationResource? {
        if usage.vertexCount > vertexCount { return .vertexCount }
        if usage.faceCount > faceCount { return .faceCount }
        if usage.cornerCount > cornerCount { return .cornerCount }
        if usage.triangleCount > triangleCount { return .triangleCount }
        if usage.byteCount > byteCount { return .byteCount }
        return nil
    }
}
