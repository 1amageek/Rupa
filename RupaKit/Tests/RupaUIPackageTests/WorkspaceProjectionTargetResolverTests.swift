import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@MainActor
@Test func workspaceProjectionTargetResolverNormalizesSketchPointHandlesForFaceProjection() throws {
    let fixture = try workspaceProjectionSketchFixture()
    let faceTarget = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .face(try workspaceTestFaceComponent(role: "body.face.target"))
    )
    let generatedEdgeTarget = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .edge(try workspaceTestEdgeComponent(role: "body.edge.generated"))
    )
    let resolver = WorkspaceProjectionTargetResolver(
        document: fixture.document,
        selection: SelectionModel(selectedTargets: [
            faceTarget,
            fixture.lineStartTarget,
            generatedEdgeTarget,
            fixture.lineTarget,
        ]),
        displayUnit: .millimeter,
        objectRegistry: .builtIn
    )

    #expect(resolver.wholeSketchCurveTarget(for: fixture.lineStartTarget) == fixture.lineTarget)
    #expect(resolver.curveProjectionTargetsForGeneratedFace(excluding: faceTarget) == [
        fixture.lineTarget,
        generatedEdgeTarget,
    ])
}

@Test func workspaceProjectionTargetResolverBuildsBodyOutlineTargetsOnlyForObjectSelection() {
    let bodyNode = SceneNode(name: "Body", reference: .body(FeatureID()))
    let sketchNode = SceneNode(name: "Sketch", reference: .sketch(FeatureID()))
    let bodyTarget = SelectionTarget(sceneNodeID: bodyNode.id)
    let sketchTarget = SelectionTarget(sceneNodeID: sketchNode.id)
    let objectResolver = WorkspaceProjectionTargetResolver(
        document: DesignDocument.empty(),
        selection: SelectionModel(selectedTargets: [bodyTarget, sketchTarget]),
        displayUnit: .millimeter,
        objectRegistry: .builtIn
    )
    let faceResolver = WorkspaceProjectionTargetResolver(
        document: DesignDocument.empty(),
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: bodyNode.id, component: .face(.bodyFaceTop)),
        ]),
        displayUnit: .millimeter,
        objectRegistry: .builtIn
    )

    #expect(objectResolver.bodyOutlineProjectionTargets(from: [sketchNode, bodyNode]) == [bodyTarget])
    #expect(faceResolver.bodyOutlineProjectionTargets(from: [bodyNode]) == [])
}

@Test func workspaceProjectionTargetResolverDeduplicatesGeneratedEdges() throws {
    let sceneNodeID = SceneNodeID()
    let generatedEdgeTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .edge(try workspaceTestEdgeComponent(role: "body.edge.generated"))
    )
    let semanticEdgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let resolver = WorkspaceProjectionTargetResolver(
        document: DesignDocument.empty(),
        selection: SelectionModel(),
        displayUnit: .millimeter,
        objectRegistry: .builtIn
    )

    #expect(resolver.generatedEdgeProjectionTargets(from: [
        generatedEdgeTarget,
        semanticEdgeTarget,
        generatedEdgeTarget,
    ]) == [generatedEdgeTarget])
}

private struct WorkspaceProjectionSketchFixture {
    var document: DesignDocument
    var lineTarget: SelectionTarget
    var lineStartTarget: SelectionTarget
}

@MainActor
private func workspaceProjectionSketchFixture() throws -> WorkspaceProjectionSketchFixture {
    let session = EditorSession()
    let lineID = SketchEntityID()
    _ = try session.execute(
        .createSketch(
            name: "Projection Line",
            sketch: Sketch(
                plane: .xy,
                entities: [
                    lineID: .line(SketchLine(
                        start: SketchPoint(
                            x: .length(0.0, .millimeter),
                            y: .length(0.0, .millimeter)
                        ),
                        end: SketchPoint(
                            x: .length(8.0, .millimeter),
                            y: .length(0.0, .millimeter)
                        )
                    )),
                ]
            ),
            geometryRole: .curve
        )
    )
    let summary = try SketchEntitySnapshotService().snapshot(document: session.document)
    let lineEntry = try #require(summary.entries.first { $0.entityID == lineID.description })
    let lineTarget = try #require(lineEntry.selectionTarget())
    let lineStartTarget = try projectionPointHandleSelectionTarget(lineEntry, handle: .lineStart)
    return WorkspaceProjectionSketchFixture(
        document: session.document,
        lineTarget: lineTarget,
        lineStartTarget: lineStartTarget
    )
}

private func projectionPointHandleSelectionTarget(
    _ entry: SketchEntitySummaryResult.EntityEntry,
    handle: SketchEntityPointHandle
) throws -> SelectionTarget {
    let sourceTarget = try #require(entry.selectionTarget())
    let pointHandle = try #require(entry.pointHandles.first { $0.handle == handle })
    return SelectionTarget(
        sceneNodeID: sourceTarget.sceneNodeID,
        component: .sketchEntity(SelectionComponentID(rawValue: pointHandle.selectionComponentID))
    )
}
