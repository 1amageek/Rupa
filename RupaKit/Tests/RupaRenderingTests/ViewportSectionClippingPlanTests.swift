import CoreGraphics
import Testing
import RupaCore
import RupaViewportScene
@testable import RupaRendering

@Test func viewportSectionClippingPlanMapsSectionBodiesToSceneItems() {
    let frontFeatureID = FeatureID()
    let intersectingFeatureID = FeatureID()
    let scene = ViewportScene(items: [
        viewportSectionClippingBodyItem(
            id: "front-item",
            featureID: frontFeatureID,
            bodyID: "runtime-front",
            persistentName: "persistent-front"
        ),
        viewportSectionClippingBodyItem(
            id: "intersecting-item",
            featureID: intersectingFeatureID,
            bodyID: nil,
            persistentName: nil
        ),
        viewportSectionClippingBodyItem(
            id: "untracked-item",
            featureID: FeatureID(),
            bodyID: nil
        ),
    ])
    let sectionPlan = SectionAnalysisClippingPlan(
        retainedSide: .front,
        bodies: [
            SectionAnalysisClippingPlan.Body(
                bodyID: "analysis-front",
                persistentName: "persistent-front",
                name: nil,
                classification: .inFront,
                action: .visible
            ),
            SectionAnalysisClippingPlan.Body(
                bodyID: "intersects",
                sourceFeatureID: intersectingFeatureID.description,
                name: nil,
                classification: .intersects,
                action: .clipped
            ),
            SectionAnalysisClippingPlan.Body(
                bodyID: "behind",
                name: nil,
                classification: .behind,
                action: .hidden
            ),
        ]
    )

    let plan = ViewportSectionClippingPlan(
        sectionPlan: sectionPlan,
        scene: scene
    )

    #expect(plan.retainedSide == .front)
    #expect(plan.items.count == 2)
    #expect(plan.action(forSceneItemID: "front-item") == .visible)
    #expect(plan.action(forSceneItemID: "intersecting-item") == .clipped)
    #expect(plan.action(forSceneItemID: "untracked-item") == nil)
    #expect(plan.items.first { $0.sceneItemID == "front-item" }?.featureID == frontFeatureID)
    #expect(plan.items.first { $0.sceneItemID == "front-item" }?.bodyID == "analysis-front")
    #expect(plan.items.first { $0.sceneItemID == "front-item" }?.persistentName == "persistent-front")
    #expect(plan.items.first { $0.sceneItemID == "intersecting-item" }?.featureID == intersectingFeatureID)
    #expect(plan.unmappedBodyIDs == ["behind"])
}

private func viewportSectionClippingBodyItem(
    id: String,
    featureID: FeatureID,
    bodyID: String?,
    persistentName: String? = nil
) -> ViewportSceneItem {
    ViewportSceneItem(
        id: id,
        featureID: featureID,
        modelBounds: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
        kind: .body(
            component: ViewportBodyComponent(
                bodyID: bodyID,
                persistentName: persistentName,
                sizeXMeters: 1.0,
                sizeYMeters: 1.0,
                sizeZMeters: 1.0,
                yMinMeters: 0.0,
                yMaxMeters: 1.0
            )
        )
    )
}
