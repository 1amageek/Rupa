public struct ViewportPickingReadinessService: Sendable {
    public init() {}

    public func summarize(
        scene: ViewportScene,
        activeBackend: ViewportPickingBackend = .projectedCPU
    ) -> ViewportPickingReadinessSummary {
        let identityTargetCount = ViewportIdentityPickIndexBuilder()
            .build(scene: scene)
            .count
        var bodyTargetCount = 0
        var generatedFaceTargetCount = 0
        var generatedEdgeTargetCount = 0
        var generatedVertexTargetCount = 0

        for item in scene.items {
            guard case .body(let component) = item.kind else {
                continue
            }
            bodyTargetCount += 1
            guard let topology = component.topology else {
                continue
            }
            generatedFaceTargetCount += topology.faces.count
            generatedEdgeTargetCount += topology.edges.count
            generatedVertexTargetCount += topology.vertices.count
        }

        return ViewportPickingReadinessSummary(
            activeBackend: activeBackend,
            bodyTargetCount: bodyTargetCount,
            generatedFaceTargetCount: generatedFaceTargetCount,
            generatedEdgeTargetCount: generatedEdgeTargetCount,
            generatedVertexTargetCount: generatedVertexTargetCount,
            identityTargetCount: identityTargetCount
        )
    }
}
