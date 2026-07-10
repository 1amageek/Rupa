import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceConstructionPlaneTargetSelectionBuilderAcceptsSingleFaceOrRegion() {
    let sceneNodeID = SceneNodeID()
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let regionTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .region(.profileRegion(featureID: FeatureID(), profileIndex: 0))
    )
    let document = DesignDocument.empty()

    let faceBuilder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: document,
        selection: SelectionModel(selectedTargets: [faceTarget])
    )
    let regionBuilder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: document,
        selection: SelectionModel(selectedTargets: [regionTarget])
    )

    #expect(faceBuilder.constructionPlaneTargets == [faceTarget])
    #expect(regionBuilder.constructionPlaneTargets == [regionTarget])
}

@Test func workspaceConstructionPlaneTargetSelectionBuilderAcceptsSavedConstructionPlanes() {
    let firstTarget = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .constructionPlane(ConstructionPlaneSourceID())
    )
    let secondTarget = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .constructionPlane(ConstructionPlaneSourceID())
    )
    let singleBuilder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: DesignDocument.empty(),
        selection: SelectionModel(selectedTargets: [firstTarget])
    )
    let pairBuilder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: DesignDocument.empty(),
        selection: SelectionModel(selectedTargets: [firstTarget, secondTarget])
    )

    #expect(singleBuilder.constructionPlaneTargets == [firstTarget])
    #expect(pairBuilder.constructionPlaneTargets == [firstTarget, secondTarget])
}

@Test func workspaceConstructionPlaneTargetSelectionBuilderAcceptsFaceEdgePair() {
    let sceneNodeID = SceneNodeID()
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let edgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let builder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: DesignDocument.empty(),
        selection: SelectionModel(selectedTargets: [faceTarget, edgeTarget])
    )

    #expect(builder.constructionPlaneTargets == [faceTarget, edgeTarget])
}

@Test func workspaceConstructionPlaneTargetSelectionBuilderAcceptsFaceAndRegionSetWithoutEdges() {
    let sceneNodeID = SceneNodeID()
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let regionTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .region(.profileRegion(featureID: FeatureID(), profileIndex: 0))
    )
    let builder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: DesignDocument.empty(),
        selection: SelectionModel(selectedTargets: [faceTarget, regionTarget])
    )

    #expect(builder.constructionPlaneTargets == [faceTarget, regionTarget])
}

@Test func workspaceConstructionPlaneTargetSelectionBuilderRejectsUnsupportedMixedTargets() {
    let sceneNodeID = SceneNodeID()
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let edgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let regionTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .region(.profileRegion(featureID: FeatureID(), profileIndex: 0))
    )
    let builder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: DesignDocument.empty(),
        selection: SelectionModel(selectedTargets: [faceTarget, edgeTarget, regionTarget])
    )

    #expect(builder.constructionPlaneTargets == nil)
}

@MainActor
@Test func workspaceConstructionPlaneTargetSelectionBuilderAcceptsSketchPointPairs() throws {
    let fixture = try workspaceConstructionPlaneSketchFixture()
    let builder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [fixture.firstPointTarget, fixture.secondPointTarget])
    )
    let mixedBuilder = WorkspaceConstructionPlaneTargetSelectionBuilder(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [fixture.firstPointTarget, fixture.lineTarget])
    )

    #expect(builder.sketchPointTargets == [fixture.firstPointTarget, fixture.secondPointTarget])
    #expect(builder.constructionPlaneTargets == [fixture.firstPointTarget, fixture.secondPointTarget])
    #expect(mixedBuilder.sketchPointTargets == [fixture.firstPointTarget])
    #expect(mixedBuilder.constructionPlaneTargets == nil)
}

private struct WorkspaceConstructionPlaneSketchFixture {
    var document: DesignDocument
    var firstPointTarget: SelectionTarget
    var secondPointTarget: SelectionTarget
    var lineTarget: SelectionTarget
}

@MainActor
private func workspaceConstructionPlaneSketchFixture() throws -> WorkspaceConstructionPlaneSketchFixture {
    let session = EditorSession()
    let firstPointID = SketchEntityID()
    let secondPointID = SketchEntityID()
    let lineID = SketchEntityID()
    _ = try session.execute(
        .createSketch(
            name: "Construction Plane Point Source",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    firstPointID: .point(SketchPoint(
                        x: .length(0.0, .millimeter),
                        y: .length(0.0, .millimeter)
                    )),
                    secondPointID: .point(SketchPoint(
                        x: .length(4.0, .millimeter),
                        y: .length(3.0, .millimeter)
                    )),
                    lineID: .line(SketchLine(
                        start: SketchPoint(
                            x: .length(0.0, .millimeter),
                            y: .length(0.0, .millimeter)
                        ),
                        end: SketchPoint(
                            x: .length(5.0, .millimeter),
                            y: .length(0.0, .millimeter)
                        )
                    )),
                ]
            ),
            geometryRole: .curve
        )
    )
    let summary = try SketchEntitySnapshotService().snapshot(document: session.document)
    let firstPointEntry = try #require(summary.entries.first { $0.entityID == firstPointID.description })
    let secondPointEntry = try #require(summary.entries.first { $0.entityID == secondPointID.description })
    let lineEntry = try #require(summary.entries.first { $0.entityID == lineID.description })
    return WorkspaceConstructionPlaneSketchFixture(
        document: session.document,
        firstPointTarget: try #require(firstPointEntry.selectionTarget()),
        secondPointTarget: try #require(secondPointEntry.selectionTarget()),
        lineTarget: try #require(lineEntry.selectionTarget())
    )
}
