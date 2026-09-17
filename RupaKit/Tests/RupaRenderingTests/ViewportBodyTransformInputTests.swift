import CoreGraphics
import RupaCore
import RupaKit
import RupaProject
import RupaViewportScene
import SwiftCAD
import Testing
import Synchronization
@testable import RupaRendering

@MainActor
@Suite struct ViewportBodyTransformInputTests {
    @Test(.timeLimit(.minutes(1)))
    func releasedPreviewSurvivesCommitUntilSourceIsObserved() async throws {
        let document = DesignDocument.empty()
        let original = ViewportSourceIdentity.document(id: document.id, generation: DocumentGeneration(1))
        let published = ViewportSourceIdentity.document(id: document.id, generation: DocumentGeneration(2))
        let mutation = try ViewportWorldTransformAlgebra.translation(.unitY)
        let handoff = ViewportBodyCommitHandoff()
        let release = Mutex(false)
        var commits = 0
        let completion = handoff.begin(source: original, mutation: mutation, occurrenceIDs: ["body"], commit: {
            commits += 1
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !release.withLock({ $0 }), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
            try #require(release.withLock { $0 })
            return published
        }, onFailure: { Issue.record($0) })
        #expect(handoff.isPending)
        #expect(handoff.transforms(for: original)["body"] == mutation)
        try await Task.sleep(for: .milliseconds(20))
        handoff.observe(original)
        #expect(handoff.transforms(for: original)["body"] == mutation)
        release.withLock { $0 = true }
        await completion.value
        #expect(commits == 1)
        // Completion can run before SwiftUI consumes the published source.
        #expect(handoff.transforms(for: original)["body"] == mutation)
        #expect(handoff.transforms(for: published).isEmpty)
        handoff.observe(published)
        #expect(!handoff.isPending)
        #expect(handoff.transforms(for: original).isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func handoffFailureNoOpAndReplacementRetireOnlyTheirOwnPreview() async throws {
        let source = ViewportSourceIdentity.document(id: DesignDocument.empty().id, generation: DocumentGeneration(1))
        let mutation = try ViewportWorldTransformAlgebra.translation(.unitY)
        let handoff = ViewportBodyCommitHandoff()
        var failures = 0
        let failure = MeshSourcePresentationRenderError(code: .failed, message: "Rejected commit.")
        await handoff.begin(source: source, mutation: mutation, occurrenceIDs: ["body"],
                            commit: { throw failure }, onFailure: { _ in failures += 1 }).value
        #expect(failures == 1)
        #expect(!handoff.isPending)
        await handoff.begin(source: source, mutation: mutation, occurrenceIDs: ["body"],
                            commit: { source }, onFailure: { Issue.record($0) }).value
        #expect(!handoff.isPending)
        let abandoned = handoff.begin(source: source, mutation: mutation, occurrenceIDs: ["body"],
                                      commit: { throw failure }, onFailure: { _ in failures += 1 })
        handoff.reset()
        let replacement = ViewportSourceIdentity.document(id: DesignDocument.empty().id, generation: DocumentGeneration(1))
        let replacementPublished = ViewportSourceIdentity.document(id: DesignDocument.empty().id, generation: DocumentGeneration(2))
        let current = handoff.begin(source: replacement, mutation: mutation, occurrenceIDs: ["new"],
                                    commit: { replacementPublished }, onFailure: { Issue.record($0) })
        await abandoned.value
        await current.value
        #expect(failures == 1)
        #expect(handoff.transforms(for: replacement)["new"] == mutation)
        #expect(handoff.transforms(for: source).isEmpty)
        handoff.observe(replacementPublished)
        #expect(!handoff.isPending)
    }

    private func input(_ action: ViewportAffordanceAction, count: Int = 1) throws -> ViewportBodyTransformInput {
        let feature = FeatureID()
        let bounds = ViewportObjectEditState(xMin: -1, xMax: 1, yMin: -1, yMax: 1, zMin: -1, zMax: 1)
        let members = try (0..<count).map { index in
            let node = SceneNodeID()
            let local = try ViewportWorldTransformAlgebra.translation(Vector3D(x: Double(index) * 4, y: 0, z: 0))
            return ViewportSpatialPreparedInteractionTarget.AffordanceBodyMember(
                occurrenceID: "body-\(index)", featureID: feature, sceneNodeID: node, modelTransform: local,
                edit: bounds, placement: .init(featureID: feature, sceneNodeID: node,
                                             baseLocalTransform: local, parentWorldTransform: .identity))
        }
        let record = try ViewportSpatialInteractionRecord(target: .affordance(
            target: .init(featureID: feature, action: action), members: members,
            groupEdit: count > 1 ? bounds : nil, placement: count == 1 ? members[0].placement : nil),
            occurrenceID: count == 1 ? members[0].occurrenceID : nil)
        return try #require(try ViewportBodyTransformInput(record: record))
    }

    @Test(arguments: ViewportCoordinateAxis.allCases)
    func translationKeepsTheNamedWorldAxisAndEveryOccurrence(axis: ViewportCoordinateAxis) throws {
        let input = try input(.translate(axis), count: 2)
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: .origin)
        let mutation = try input.mutation(from: measure.projected(.origin),
            to: measure.projected(Point3D.origin + axis.unitVector * 0.25), measure: measure)
        let targets = try input.commits(mutation: mutation)
        #expect(targets.count == 2)
        #expect(targets[0].sceneNodeID != targets[1].sceneNodeID)
        #expect(targets[0].featureID == targets[1].featureID)
        for target in targets {
            let before = try ViewportWorldTransformAlgebra.transformedPoint(.origin, by: target.baseLocalTransform)
            let after = try ViewportWorldTransformAlgebra.transformedPoint(.origin, by: target.localTransform)
            #expect(((after - before) - axis.unitVector * 0.25).length < 1e-9)
        }
    }

    @Test func rotationCommitsGeometryRatherThanOnlyAnOrientationPreview() throws {
        let input = try input(.rotate(.z))
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: .origin)
        let mutation = try input.mutation(from: measure.projected(Point3D(x: 1, y: 0, z: 0)),
            to: measure.projected(Point3D(x: 0, y: 1, z: 0)), measure: measure)
        let target = try #require(try input.commits(mutation: mutation).first)
        let rotated = try ViewportWorldTransformAlgebra.transformedPoint(Point3D(x: 1, y: 0, z: 0), by: target.localTransform)
        #expect((rotated - Point3D(x: 0, y: 1, z: 0)).length < 1e-9)
    }

    @Test(arguments: [true, false])
    func axisScalingKeepsItsPivotAndRejectsCollapse(centered: Bool) throws {
        let input = try input(centered ? .centerScale(.x) : .oneSidedScale(.x))
        let measure = try ViewportOrthographicAffordanceMeasure.isometric(at: .origin)
        let mutation = try input.mutation(from: measure.projected(.origin),
            to: measure.projected(Point3D(x: 0.5, y: 0, z: 0)), measure: measure)
        let low = try ViewportWorldTransformAlgebra.transformedPoint(Point3D(x: -1, y: 0, z: 0), by: mutation)
        let high = try ViewportWorldTransformAlgebra.transformedPoint(Point3D(x: 1, y: 0, z: 0), by: mutation)
        #expect(abs(high.x - 1.5) < 1e-9)
        #expect(abs(low.x - (centered ? -1.5 : -1)) < 1e-9)
        #expect(throws: Error.self) {
            _ = try input.mutation(from: measure.projected(.origin),
                to: measure.projected(Point3D(x: -3, y: 0, z: 0)), measure: measure)
        }
    }

    @Test func parentChangeInvalidatesAnUnchangedChildLocalFrame() throws {
        var document = DesignDocument.empty()
        let parent = try #require(document.productMetadata.rootSceneNodeIDs.first)
        let node = SceneNodeID()
        let feature = FeatureID()
        document.productMetadata.sceneNodes[node] = SceneNode(id: node, name: "Body", reference: .body(feature))
        document.productMetadata.sceneNodes[parent]?.childIDs.append(node)
        let target = ViewportBodyPlacementDragTarget(featureID: feature, sceneNodeID: node,
            baseLocalTransform: .identity,
            localTransform: try ViewportWorldTransformAlgebra.translation(.unitX))
        try target.validate(in: document)
        document.productMetadata.sceneNodes[parent]?.localTransform = try ViewportWorldTransformAlgebra.rotation(
            axis: .unitZ, radians: .pi / 2, about: .origin)
        #expect(document.productMetadata.sceneNodes[node]?.localTransform == .identity)
        #expect(throws: Error.self) { try target.validate(in: document) }
    }

    @Test(.timeLimit(.minutes(1)))
    func groupPlacementIsOneAtomicUndoableWorkspaceTransaction() async throws {
        let session = EditorSession()
        _ = try #require(session.createDefaultExtrudedRectangle())
        var document = session.document
        let first = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body
        })
        let second = SceneNode(id: SceneNodeID(), name: "Second occurrence", reference: first.reference)
        document.productMetadata.sceneNodes[second.id] = second
        document.productMetadata.rootSceneNodeIDs.append(second.id)
        let controller = try ProjectController(document: document,
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
            projector: DesignDocumentProjectBridge())
        let workspace = ProjectWorkspace(project: controller)
        let base = try await workspace.evaluate()
        let transform = try ViewportWorldTransformAlgebra.translation(.unitY)
        let planner = DefaultProjectWorkspaceActionPlanner()
        let batch = try planner.source(name: "transformBodyPlacements", commands: [
            .setSceneNodeTransform(id: first.id, localTransform: transform),
            .setSceneNodeTransform(id: second.id, localTransform: transform)
        ], from: base)
        _ = try await workspace.perform(batch)
        let changed = try #require(workspace.view)
        #expect(changed.document.document.productMetadata.sceneNodes[first.id]?.localTransform == transform)
        #expect(changed.document.document.productMetadata.sceneNodes[second.id]?.localTransform == transform)
        #expect(changed.transactionRevision.value == base.transactionRevision.value + 1)
        await #expect(throws: Error.self) { _ = try await workspace.perform(batch) }
        let undone = try await workspace.undo()
        #expect(undone.document.document.productMetadata == document.productMetadata)
        #expect(!undone.canUndo)
        let redone = try await workspace.redo()
        #expect(redone.document.document.productMetadata == changed.document.document.productMetadata)
        let invalid = try planner.source(name: "invalidBodyBatch", commands: [
            .setSceneNodeTransform(id: first.id, localTransform: .identity),
            .setSceneNodeTransform(id: SceneNodeID(), localTransform: transform)
        ], from: redone)
        await #expect(throws: Error.self) { _ = try await workspace.perform(invalid) }
        #expect(workspace.view?.document.document.productMetadata == redone.document.document.productMetadata)
        #expect(workspace.view?.transactionRevision == redone.transactionRevision)
    }

    @Test func previewMovesOnlyTheAddressedOccurrenceAndKeepsItsMesh() throws {
        let feature = FeatureID()
        let positions = [Point3D.origin, Point3D(x: 2, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)]
        let component = ViewportBodyComponent(sizeXMeters: 2, sizeYMeters: 1, sizeZMeters: 1,
            yMinMeters: 0, yMaxMeters: 1, mesh: .init(positions: positions, indices: [0, 1, 2]))
        let first = ViewportSceneItem(id: "selected", featureID: feature, sceneNodeID: SceneNodeID(),
            modelBounds: CGRect(x: 0, y: 0, width: 2, height: 1), kind: .body(component: component))
        var other = first
        other.id = "unselected"
        other.sceneNodeID = SceneNodeID()
        other.modelTransform = try ViewportWorldTransformAlgebra.translation(Vector3D(x: 4, y: 0, z: 0))
        let mutation = try ViewportWorldTransformAlgebra.translation(.unitY)
        let snapshot = ViewportSpatialOverlaySemanticSnapshot(scene: .init(items: [first, other]),
            interaction: .init(selectedFeatureIDs: [], selectedSceneNodeIDs: [], hoveredFeatureIDs: [],
                hoveredSceneNodeIDs: [], selectedSketchEntities: [], previewSketchEntities: [],
                hoveredSketchEntity: nil, selectedSketchRegions: [], previewSketchRegions: [], hoveredSketchRegion: nil),
            editedBodies: [:], bodyPreviewTransforms: [first.id: mutation],
            world: .init(modelBounds: first.modelBounds), measurement: nil,
            drawsLegacyBodies: true, drawsDragPreviewBodies: false)
        let result = try ViewportSpatialOverlayProducer.makeInput(from: snapshot,
            renderOrigin: .origin, retainedSurfaceByteCount: 0, topologyRevision: 1)
        let meshes = result.meshes.filter { $0.family == .body }
        #expect(meshes.count == 2)
        #expect(meshes[0].value.positions == positions.map { $0 + Vector3D.unitY })
        #expect(meshes[1].value.positions == positions.map { $0 + Vector3D(x: 4, y: 0, z: 0) })
        #expect(meshes.allSatisfy { $0.value.indices == [0, 1, 2] })
    }
}
