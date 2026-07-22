import CoreGraphics
import Testing
import RupaCore
import RupaViewportScene
import SwiftCAD
@testable import RupaRendering

@Test func viewportSectionClippingPlanMapsSectionBodiesToSceneItems() throws {
    let frontFeatureID = FeatureID()
    let intersectingFeatureID = FeatureID()
    let frontStableReference = viewportSectionBodyStableReference(featureID: frontFeatureID)
    try frontStableReference.validate()
    let scene = ViewportScene(items: [
        viewportSectionClippingBodyItem(
            id: "front-item",
            featureID: frontFeatureID,
            bodyID: "runtime-front",
            stableReference: frontStableReference
        ),
        viewportSectionClippingBodyItem(
            id: "intersecting-item",
            featureID: intersectingFeatureID,
            bodyID: nil,
            stableReference: nil
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
                stableReference: frontStableReference,
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
    #expect(plan.items.first { $0.sceneItemID == "front-item" }?.stableReference == frontStableReference)
    #expect(plan.items.first { $0.sceneItemID == "intersecting-item" }?.featureID == intersectingFeatureID)
    #expect(plan.unmappedBodyIDs == ["behind"])
}

@Test func viewportSectionClippingPlanRemovesHiddenBodiesFromRenderedScene() {
    let visibleFeatureID = FeatureID()
    let hiddenFeatureID = FeatureID()
    let scene = ViewportScene(items: [
        viewportSectionClippingBodyItem(
            id: "visible-item",
            featureID: visibleFeatureID,
            bodyID: "visible"
        ),
        viewportSectionClippingBodyItem(
            id: "hidden-item",
            featureID: hiddenFeatureID,
            bodyID: "hidden"
        ),
    ])
    let sectionPlan = SectionAnalysisClippingPlan(
        retainedSide: .front,
        bodies: [
            SectionAnalysisClippingPlan.Body(
                bodyID: "visible",
                name: nil,
                classification: .inFront,
                action: .visible
            ),
            SectionAnalysisClippingPlan.Body(
                bodyID: "hidden",
                name: nil,
                classification: .behind,
                action: .hidden
            ),
        ]
    )

    let renderedScene = ViewportSectionClippingPlan(
        sectionPlan: sectionPlan,
        scene: scene
    )
    .renderedScene(from: scene)

    #expect(renderedScene.items.map(\.id) == ["visible-item"])
}

private func viewportSectionClippingBodyItem(
    id: String,
    featureID: FeatureID,
    bodyID: String?,
    stableReference: StableSubshapeReference? = nil
) -> ViewportSceneItem {
    ViewportSceneItem(
        id: id,
        featureID: featureID,
        modelBounds: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
        kind: .body(
            component: ViewportBodyComponent(
                bodyID: bodyID,
                stableReference: stableReference,
                sizeXMeters: 1.0,
                sizeYMeters: 1.0,
                sizeZMeters: 1.0,
                yMinMeters: 0.0,
                yMaxMeters: 1.0
            )
        )
    )
}

private func viewportSectionBodyStableReference(
    featureID: FeatureID
) -> StableSubshapeReference {
    StableSubshapeReference(
        subshapeID: SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        ),
        geometrySignature: .body(
            BodyGeometrySignature(
                kind: .solid,
                shells: [
                    ShellGeometrySignature(
                        orientation: .forward,
                        faces: [
                            FaceGeometrySignature(
                                surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                                orientation: .forward,
                                loops: []
                            ),
                        ]
                    ),
                ]
            )
        )
    )
}
