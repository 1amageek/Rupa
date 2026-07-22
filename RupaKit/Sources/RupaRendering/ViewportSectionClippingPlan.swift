import Foundation
import RupaCore
import RupaViewportScene

public struct ViewportSectionClippingPlan: Equatable {
    public struct Item: Equatable, Identifiable {
        public var id: String
        public var sceneItemID: String
        public var featureID: FeatureID
        public var bodyID: String
        public var sourceFeatureID: String?
        public var stableReference: StableSubshapeReference?
        public var action: SectionAnalysisClippingPlan.BodyAction

        public init(
            sceneItemID: String,
            featureID: FeatureID,
            bodyID: String,
            sourceFeatureID: String? = nil,
            stableReference: StableSubshapeReference? = nil,
            action: SectionAnalysisClippingPlan.BodyAction
        ) {
            self.id = sceneItemID
            self.sceneItemID = sceneItemID
            self.featureID = featureID
            self.bodyID = bodyID
            self.sourceFeatureID = sourceFeatureID
            self.stableReference = stableReference
            self.action = action
        }
    }

    public var retainedSide: SectionAnalysisRetainedSide
    public var items: [Item]
    public var unmappedBodyIDs: [String]

    public init(
        retainedSide: SectionAnalysisRetainedSide,
        items: [Item],
        unmappedBodyIDs: [String]
    ) {
        self.retainedSide = retainedSide
        self.items = items
        self.unmappedBodyIDs = unmappedBodyIDs
    }

    public init(
        sectionPlan: SectionAnalysisClippingPlan,
        scene: ViewportScene
    ) {
        let items = scene.items.compactMap { item -> Item? in
            guard case .body(let component) = item.kind,
                  let body = Self.matchingBody(
                    item: item,
                    component: component,
                    bodies: sectionPlan.bodies
                  ) else {
                return nil
            }
            return Item(
                sceneItemID: item.id,
                featureID: item.featureID,
                bodyID: body.bodyID,
                sourceFeatureID: body.sourceFeatureID,
                stableReference: body.stableReference,
                action: body.action
            )
        }
        let mappedBodyIDs = Set(items.map(\.bodyID))
        let unmappedBodyIDs = sectionPlan.bodies
            .map(\.bodyID)
            .filter { !mappedBodyIDs.contains($0) }
            .sorted()
        self.init(
            retainedSide: sectionPlan.retainedSide,
            items: items,
            unmappedBodyIDs: unmappedBodyIDs
        )
    }

    public func action(forSceneItemID sceneItemID: String) -> SectionAnalysisClippingPlan.BodyAction? {
        items.first { $0.sceneItemID == sceneItemID }?.action
    }

    public func renderedScene(from scene: ViewportScene) -> ViewportScene {
        ViewportScene(items: scene.items.filter { item in
            action(forSceneItemID: item.id) != .hidden
        })
    }

    private static func matchingBody(
        item: ViewportSceneItem,
        component: ViewportBodyComponent,
        bodies: [SectionAnalysisClippingPlan.Body]
    ) -> SectionAnalysisClippingPlan.Body? {
        if let stableReference = component.stableReference,
           let body = bodies.first(where: { $0.stableReference == stableReference }) {
            return body
        }
        let sourceFeatureIDs = [
            item.featureID.description,
            item.sourceFeatureID?.description,
        ].compactMap { $0 }
        if let body = bodies.first(where: { body in
            guard let sourceFeatureID = body.sourceFeatureID else {
                return false
            }
            return sourceFeatureIDs.contains(sourceFeatureID)
        }) {
            return body
        }
        if let bodyID = component.bodyID,
           let body = bodies.first(where: { $0.bodyID == bodyID }) {
            return body
        }
        return nil
    }
}
