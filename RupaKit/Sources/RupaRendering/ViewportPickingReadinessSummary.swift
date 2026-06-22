public struct ViewportPickingReadinessSummary: Codable, Equatable, Sendable {
    public var activeBackend: ViewportPickingBackend
    public var requiredBackend: ViewportPickingBackend
    public var bodyTargetCount: Int
    public var generatedFaceTargetCount: Int
    public var generatedEdgeTargetCount: Int
    public var generatedVertexTargetCount: Int

    public init(
        activeBackend: ViewportPickingBackend,
        requiredBackend: ViewportPickingBackend = .identityBuffer,
        bodyTargetCount: Int,
        generatedFaceTargetCount: Int,
        generatedEdgeTargetCount: Int,
        generatedVertexTargetCount: Int
    ) {
        self.activeBackend = activeBackend
        self.requiredBackend = requiredBackend
        self.bodyTargetCount = bodyTargetCount
        self.generatedFaceTargetCount = generatedFaceTargetCount
        self.generatedEdgeTargetCount = generatedEdgeTargetCount
        self.generatedVertexTargetCount = generatedVertexTargetCount
    }

    public var supportsObjectTargets: Bool {
        bodyTargetCount > 0
    }

    public var supportsGeneratedFaceTargets: Bool {
        generatedFaceTargetCount > 0
    }

    public var supportsGeneratedEdgeTargets: Bool {
        generatedEdgeTargetCount > 0
    }

    public var supportsGeneratedVertexTargets: Bool {
        generatedVertexTargetCount > 0
    }

    public var supportsGeneratedTopologyTargets: Bool {
        supportsGeneratedFaceTargets || supportsGeneratedEdgeTargets || supportsGeneratedVertexTargets
    }

    public var isExactIdentityBacked: Bool {
        activeBackend.isExactIdentityBacked
    }

    public var activeBackendTitle: String {
        activeBackend.title
    }

    public var nextBackendTitle: String {
        isExactIdentityBacked ? "Ready" : requiredBackend.title
    }
}
