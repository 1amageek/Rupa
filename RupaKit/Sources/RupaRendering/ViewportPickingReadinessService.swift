import RupaViewportScene
public struct ViewportPickingReadinessService: Sendable {
    public init() {}

    public func summarize(
        scene: ViewportScene,
        layout: ViewportLayout? = nil,
        activeBackend: ViewportPickingBackend = .projectedCPU,
        sketchControlPointHitPolicy: ViewportSketchControlPointHitPolicy = .all,
        selectionHitPolicy: ViewportSelectionHitPolicy = .all,
        renderBudget: ViewportIdentityHitResolver.RenderBudget = .standard
    ) -> ViewportPickingReadinessSummary {
        let index = ViewportIdentityPickIndexBuilder(
            sketchControlPointHitPolicy: sketchControlPointHitPolicy,
            selectionHitPolicy: selectionHitPolicy
        )
        .build(scene: scene)
        let identityTargetCount = index.count
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
        let identityRenderCost = layout.map {
            renderCost(
                scene: scene,
                layout: $0,
                index: index,
                selectionHitPolicy: selectionHitPolicy
            )
        }
        let identityBudgetRejection = identityRenderCost.flatMap {
            renderBudget.rejection(for: $0)
        }

        return ViewportPickingReadinessSummary(
            activeBackend: activeBackend,
            bodyTargetCount: bodyTargetCount,
            generatedFaceTargetCount: generatedFaceTargetCount,
            generatedEdgeTargetCount: generatedEdgeTargetCount,
            generatedVertexTargetCount: generatedVertexTargetCount,
            identityTargetCount: identityTargetCount,
            identityBudgetCalibration: renderBudget.calibration,
            identityRenderCost: identityRenderCost,
            identityBudgetRejection: identityBudgetRejection
        )
    }

    private func renderCost(
        scene: ViewportScene,
        layout: ViewportLayout,
        index: ViewportIdentityPickIndex,
        selectionHitPolicy: ViewportSelectionHitPolicy
    ) -> ViewportIdentityHitResolver.RenderCost {
        let renderWidth = max(Int(layout.viewportSize.width.rounded(.up)), 1)
        let renderHeight = max(Int(layout.viewportSize.height.rounded(.up)), 1)
        let planEstimate = ViewportIdentityPickRenderPlanBuilder()
            .estimate(
                scene: scene,
                layout: layout,
                index: index,
                selectionHitPolicy: selectionHitPolicy
            )
        return ViewportIdentityHitResolver.RenderCost(
            viewportWidth: renderWidth,
            viewportHeight: renderHeight,
            pixelCount: ViewportIdentityHitResolver.RenderCost.saturatedProduct(
                renderWidth,
                renderHeight
            ),
            drawItemCount: planEstimate.drawItemCount,
            encodedPointCount: planEstimate.encodedPointCount,
            identityRecordCount: index.count
        )
    }
}
