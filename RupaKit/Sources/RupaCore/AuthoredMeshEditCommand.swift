import RupaGeometry

/// A complete immutable Mesh plan applied to one source authority.
public struct AuthoredMeshEditCommand: Codable, Equatable, Sendable {
    public let target: AuthoredMeshEditTarget
    public let plan: MeshEditPlan

    public init(
        target: AuthoredMeshEditTarget,
        plan: MeshEditPlan
    ) {
        self.target = target
        self.plan = plan
    }
}
