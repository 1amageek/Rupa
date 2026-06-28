import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceSplineControlPointSelectionResolverKeepsValidUniqueControlPointIndexesInSelectionOrder() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let otherFeatureID = FeatureID()
    let entity = splineEntity(
        sceneNodeID: sceneNodeID,
        featureID: featureID,
        entityID: entityID,
        controlPointCount: 4
    )
    let resolver = WorkspaceSplineControlPointSelectionResolver(
        selection: SelectionModel(selectedTargets: [
            controlPointTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: entityID, index: 2),
            controlPointTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: entityID, index: 1),
            controlPointTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: entityID, index: 2),
            controlPointTarget(sceneNodeID: sceneNodeID, featureID: otherFeatureID, entityID: entityID, index: 3),
            controlPointTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: entityID, index: 8),
            SelectionTarget(sceneNodeID: sceneNodeID),
        ])
    )

    #expect(resolver.selectedControlPointIndexes(for: entity) == [2, 1])
}

@Test func workspaceSplineControlPointSelectionResolverBuildsSlideInputOnlyForSplineSelections() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let spline = splineEntity(
        sceneNodeID: sceneNodeID,
        featureID: featureID,
        entityID: entityID,
        controlPointCount: 3
    )
    var line = spline
    line.entityKind = "line"
    let resolver = WorkspaceSplineControlPointSelectionResolver(
        selection: SelectionModel(selectedTargets: [
            controlPointTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: entityID, index: 0),
            controlPointTarget(sceneNodeID: sceneNodeID, featureID: featureID, entityID: entityID, index: 2),
        ])
    )

    #expect(resolver.slideInput(for: spline) == WorkspaceSplineControlPointSlideInput(
        target: spline.target,
        controlPointIndexes: [0, 2]
    ))
    #expect(resolver.slideInput(for: line) == nil)
    #expect(resolver.slideInput(for: nil) == nil)
}

@Test func workspaceSplineControlPointSelectionResolverReturnsNilWithoutSelectedControlPoints() {
    let sceneNodeID = SceneNodeID()
    let featureID = FeatureID()
    let entityID = SketchEntityID()
    let entity = splineEntity(
        sceneNodeID: sceneNodeID,
        featureID: featureID,
        entityID: entityID,
        controlPointCount: 2
    )
    let resolver = WorkspaceSplineControlPointSelectionResolver(selection: SelectionModel())

    #expect(resolver.selectedControlPointIndexes(for: entity) == [])
    #expect(resolver.slideInput(for: entity) == nil)
}

private func splineEntity(
    sceneNodeID: SceneNodeID,
    featureID: FeatureID,
    entityID: SketchEntityID,
    controlPointCount: Int
) -> InspectorSketchEntity {
    InspectorSketchEntity(
        target: SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))
        ),
        sourceFeatureID: featureID,
        entityID: entityID,
        sourceFeatureName: "Spline",
        entityKind: "spline",
        controlPoints: (0..<controlPointCount).map { index in
            SketchEntitySummaryResult.Point(x: Double(index), y: Double(index))
        }
    )
}

private func controlPointTarget(
    sceneNodeID: SceneNodeID,
    featureID: FeatureID,
    entityID: SketchEntityID,
    index: Int
) -> SelectionTarget {
    SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .sketchEntity(
            .sketchControlPoint(
                featureID: featureID,
                entityID: entityID,
                index: index
            )
        )
    )
}
