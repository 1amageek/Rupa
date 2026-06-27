import RupaViewportScene
public struct ViewportPickingReadinessSummary: Codable, Equatable, Sendable {
    public var activeBackend: ViewportPickingBackend
    public var requiredBackend: ViewportPickingBackend
    public var bodyTargetCount: Int
    public var generatedFaceTargetCount: Int
    public var generatedEdgeTargetCount: Int
    public var generatedVertexTargetCount: Int
    public var identityTargetCount: Int
    public var identityRenderCost: ViewportIdentityHitResolver.RenderCost?
    public var identityBudgetRejection: ViewportIdentityHitResolver.RenderBudgetRejection?

    public init(
        activeBackend: ViewportPickingBackend,
        requiredBackend: ViewportPickingBackend = .identityBuffer,
        bodyTargetCount: Int,
        generatedFaceTargetCount: Int,
        generatedEdgeTargetCount: Int,
        generatedVertexTargetCount: Int,
        identityTargetCount: Int = 0,
        identityRenderCost: ViewportIdentityHitResolver.RenderCost? = nil,
        identityBudgetRejection: ViewportIdentityHitResolver.RenderBudgetRejection? = nil
    ) {
        self.activeBackend = activeBackend
        self.requiredBackend = requiredBackend
        self.bodyTargetCount = bodyTargetCount
        self.generatedFaceTargetCount = generatedFaceTargetCount
        self.generatedEdgeTargetCount = generatedEdgeTargetCount
        self.generatedVertexTargetCount = generatedVertexTargetCount
        self.identityTargetCount = identityTargetCount
        self.identityRenderCost = identityRenderCost
        self.identityBudgetRejection = identityBudgetRejection
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

    public var supportsIdentityTargetIndex: Bool {
        identityTargetCount > 0
    }

    public var hasIdentityBudgetEstimate: Bool {
        identityRenderCost != nil
    }

    public var isIdentityRenderWithinBudget: Bool {
        identityBudgetRejection == nil
    }

    public var isExactIdentityBacked: Bool {
        activeBackend.isExactIdentityBacked
    }

    public var activeBackendTitle: String {
        activeBackend.title
    }

    public var nextBackendTitle: String {
        if isExactIdentityBacked {
            return "Ready"
        }
        if identityBudgetRejection != nil {
            return "CPU"
        }
        return requiredBackend.title
    }

    public var identityBudgetStatusTitle: String {
        guard let rejection = identityBudgetRejection else {
            return hasIdentityBudgetEstimate ? "Within budget" : "Unknown"
        }
        switch rejection.limit {
        case .pixelCount:
            return "Pixel budget exceeded"
        case .drawItemCount:
            return "Draw-item budget exceeded"
        case .encodedPointCount:
            return "Encoded-point budget exceeded"
        }
    }
}
