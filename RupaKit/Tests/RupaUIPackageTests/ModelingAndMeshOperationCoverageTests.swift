import Testing
import RupaCore
import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
import SwiftCAD
@testable import RupaUI

@Suite("Additional modeling and Mesh operation coverage", .timeLimit(.minutes(1)))
struct ModelingAndMeshOperationCoverageTests {
    @Test func cylinderDraftReachesExistingCADCommandAndPreservesDimensions() throws {
        var cylinder = makeModelingDraft(.cylinder)
        cylinder.width = "4 mm"
        cylinder.distance = "12 mm"
        let cylinderCommand = try cylinder.command(in: .empty())
        guard case .createExtrudedCircle(_, _, _, let radius, let depth, _) = cylinderCommand else {
            Issue.record("Cylinder draft must use the existing circle extrusion command.")
            return
        }
        #expect(radius == .length(0.004, .meter))
        #expect(depth == .length(0.012, .meter))
        let cylinderStore = CADDocumentStore(document: .empty())
        _ = try cylinderStore.apply(cylinderCommand)
        let cylinderEvaluation = try CADPipeline.modelingDefault(for: cylinderStore.document)
            .evaluate(cylinderStore.document.cadDocument)
        #expect(cylinderEvaluation.brep.bodies.count == 1)
        let cylinderVolume = try measuredSolidVolume(in: cylinderStore.document)
        #expect(abs(cylinderVolume - Double.pi * 0.004 * 0.004 * 0.012) < 1.0e-12)
    }

    @Test func sphereDraftReachesExistingCADCommandAndPreservesRadius() throws {
        var sphere = makeModelingDraft(.sphere)
        sphere.width = "6 mm"
        let sphereCommand = try sphere.command(in: .empty())
        guard case .createAnalyticSphere(_, let center, let radius) = sphereCommand else {
            Issue.record("Sphere draft must use the existing analytic sphere command.")
            return
        }
        #expect(center == .origin)
        #expect(radius == 0.006)
        let sphereStore = CADDocumentStore(document: .empty())
        _ = try sphereStore.apply(sphereCommand)
        let sphereEvaluation = try CADPipeline.modelingDefault(for: sphereStore.document)
            .evaluate(sphereStore.document.cadDocument)
        #expect(sphereEvaluation.brep.bodies.count == 1)
        let sphereVolume = try measuredSolidVolume(in: sphereStore.document)
        #expect(abs(sphereVolume - (4.0 * Double.pi * 0.006 * 0.006 * 0.006 / 3.0)) < 1.0e-12)
    }

    @Test func booleanDraftReachesExistingCADCommandAndPreservesUnionVolume() throws {
        var booleanDocument = DesignDocument.empty()
        let targetFeature = try addBooleanBody(
            to: &booleanDocument,
            name: "Target",
            minX: -20,
            minY: -10,
            maxX: 20,
            maxY: 10
        )
        let toolFeature = try addBooleanBody(
            to: &booleanDocument,
            name: "Tool",
            minX: 0,
            minY: -10,
            maxX: 40,
            maxY: 10
        )
        let targetNode = try #require(booleanDocument.productMetadata.sceneNodes.values.first {
            $0.reference == .body(targetFeature)
        })
        let toolNode = try #require(booleanDocument.productMetadata.sceneNodes.values.first {
            $0.reference == .body(toolFeature)
        })
        var boolean = makeModelingDraft(
            .boolean,
            targets: [
                SelectionTarget(sceneNodeID: targetNode.id),
                SelectionTarget(sceneNodeID: toolNode.id),
            ]
        )
        boolean.booleanOperation = .union
        let booleanCommand = try boolean.command(in: booleanDocument)
        guard case .createBoolean(_, let targets, let tool, let operation, let keepTools) = booleanCommand else {
            Issue.record("Boolean draft must use the existing Boolean command.")
            return
        }
        #expect(targets.map(\.featureID) == [targetFeature])
        #expect(tool.featureID == toolFeature)
        #expect(operation == .union)
        #expect(keepTools == false)
        let booleanStore = CADDocumentStore(document: booleanDocument)
        _ = try booleanStore.apply(booleanCommand)
        let booleanEvaluation = try CADPipeline.modelingDefault(for: booleanStore.document)
            .evaluate(booleanStore.document.cadDocument)
        #expect(booleanEvaluation.brep.bodies.count == 1)
        let booleanVolume = try measuredSolidVolume(in: booleanStore.document)
        #expect(abs(booleanVolume - 12.0e-6) < 1.0e-12)
    }

    @Test func sweepDraftReachesExistingCADCommandAndEvaluatesGeometry() throws {
        var sweepDocument = DesignDocument.empty()
        let profile = try addProfile(to: &sweepDocument, z: 0)
        let pathFeature = try sweepDocument.createLineSketch(
            name: "Sweep Path",
            plane: .yz,
            start: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            end: SketchPoint(x: .length(0, .meter), y: .length(0.02, .meter))
        )
        let pathNode = try #require(sweepDocument.productMetadata.sceneNodes.values.first {
            $0.reference == .sketch(pathFeature)
        })
        var sweep = makeModelingDraft(
            .sweep,
            targets: [
                profile.target,
                SelectionTarget(sceneNodeID: pathNode.id),
            ]
        )
        sweep.name = "Sweep"
        let sweepCommand = try sweep.command(in: sweepDocument)
        guard case .createSweep(_, let sections, let path, _, _, _) = sweepCommand else {
            Issue.record("Sweep draft must use the existing sweep command.")
            return
        }
        #expect(sections.count == 1)
        #expect(path.featureID == pathFeature)
        let sweepStore = CADDocumentStore(document: sweepDocument)
        _ = try sweepStore.apply(sweepCommand)
        let sweepEvaluation = try CADPipeline.modelingDefault(for: sweepStore.document)
            .evaluate(sweepStore.document.cadDocument)
        #expect(sweepEvaluation.brep.bodies.count == 1)
        #expect(sweepEvaluation.brep.faces.count > 0)
    }

    @MainActor
    @Test func meshPositionReachesWorkspacePreviewAndCommit() async throws {
        let workspace = try await makeMeshCoverageWorkspace()
        let initial = try #require(workspace.view)
        let initialItem = try #require(initial.viewport.items.first)
        let initialAsset = try #require(initial.document.document.authoredMeshAssets[initialItem.mesh.identity])
        let firstVertex = initialAsset.source.vertexIDs[0]

        var position = MeshOperationDraft(
            sourceID: initialAsset.id,
            contentIdentity: initialAsset.contentIdentity,
            occurrenceID: initialItem.id,
            unit: .millimeter
        )
        position.kind = .position
        position.elements = [.vertex(firstVertex)]
        position.coordinates = ["1 mm", "0", "0"]
        let positionRequest = try position.request(from: initial)
        let positionPreview = try await workspace.previewRenderPayload(positionRequest)
        let positionedAsset = try #require(positionPreview.document.authoredMeshAssets[initialAsset.id])
        let positionedIndex = try #require(positionedAsset.source.vertexIDs.firstIndex(of: firstVertex))
        #expect(positionedAsset.source.vertexPositions[positionedIndex] == GeometryPoint3D(x: 0.001, y: 0, z: 0))
        _ = try await workspace.commit(positionRequest)
        let committed = try #require(workspace.view)
        let committedAsset = try #require(committed.document.document.authoredMeshAssets[initialAsset.id])
        let committedIndex = try #require(committedAsset.source.vertexIDs.firstIndex(of: firstVertex))
        #expect(committedAsset.source.vertexPositions[committedIndex] == GeometryPoint3D(x: 0.001, y: 0, z: 0))
    }

    @MainActor
    @Test func meshDeleteReachesWorkspacePreviewAndCommit() async throws {
        let workspace = try await makeMeshCoverageWorkspace()
        let initial = try #require(workspace.view)
        let item = try #require(initial.viewport.items.first)
        let asset = try #require(initial.document.document.authoredMeshAssets[item.mesh.identity])
        let face = try #require(asset.source.faceIDs.first)
        var deletion = MeshOperationDraft(
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity,
            occurrenceID: item.id,
            unit: .millimeter
        )
        deletion.kind = .delete
        deletion.elements = [.face(face)]
        let deletionRequest = try deletion.request(from: initial)
        let deletionPreview = try await workspace.previewRenderPayload(deletionRequest)
        let deletedAsset = try #require(deletionPreview.document.authoredMeshAssets[asset.id])
        #expect(deletedAsset.source.faceIDs.isEmpty)
        _ = try await workspace.commit(deletionRequest)
        #expect(try #require(workspace.view).document.document.authoredMeshAssets[asset.id]?.source.faceIDs.isEmpty == true)
    }

    @MainActor
    @Test func meshAddFaceReachesWorkspacePreviewAndCommit() async throws {
        let workspace = try await makeMeshCoverageWorkspace()
        let initial = try #require(workspace.view)
        let item = try #require(initial.viewport.items.first)
        let asset = try #require(initial.document.document.authoredMeshAssets[item.mesh.identity])
        var addition = MeshOperationDraft(
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity,
            occurrenceID: item.id,
            unit: .millimeter
        )
        addition.kind = .addFace
        addition.elements = asset.source.vertexIDs.reversed().map { .vertex($0) }
        let additionRequest = try addition.request(from: initial)
        let additionPreview = try await workspace.previewRenderPayload(additionRequest)
        let addedAsset = try #require(additionPreview.document.authoredMeshAssets[asset.id])
        #expect(addedAsset.source.faceIDs.count == asset.source.faceIDs.count + 1)
        _ = try await workspace.commit(additionRequest)
        #expect(try #require(workspace.view).document.document.authoredMeshAssets[asset.id]?.source.faceIDs.count == asset.source.faceIDs.count + 1)
    }

    @MainActor
    @Test func meshTopologyOperationsCommitOnADenselyAttributedMesh() async throws {
        // A Mesh made editable from CAD always carries dense vertex
        // attributes, so every topology operation the panel offers has to
        // commit on one.
        let deleted = try await commitAttributedMeshDraft { draft, asset in
            draft.kind = .delete
            draft.elements = asset.source.faceIDs.first.map { [.face($0)] } ?? []
        }
        #expect(deleted.after.source.faceIDs.isEmpty)
        #expect(deleted.after.source.attributes == deleted.before.source.attributes)

        let added = try await commitAttributedMeshDraft { draft, asset in
            draft.kind = .addFace
            draft.elements = asset.source.vertexIDs.reversed().map { .vertex($0) }
        }
        #expect(added.after.source.faceIDs.count == added.before.source.faceIDs.count + 1)
        #expect(added.after.source.attributes == added.before.source.attributes)

        let extruded = try await commitAttributedMeshDraft { draft, asset in
            draft.kind = .extrude
            draft.coordinates = ["0", "0", "1"]
            draft.elements = asset.source.faceIDs.map { .face($0) }
        }
        #expect(extruded.after.source.vertexIDs.count > extruded.before.source.vertexIDs.count)
        // MeshSource validates a dense layer against its domain count, so the
        // committed source proves every extruded vertex inherited a normal.
        #expect(extruded.after.source.attributes.layer(for: "cad.normal") != nil)
    }

    @MainActor
    private func commitAttributedMeshDraft(
        _ configure: (inout MeshOperationDraft, AuthoredMeshAsset) -> Void
    ) async throws -> (before: AuthoredMeshAsset, after: AuthoredMeshAsset) {
        let workspace = try await makeMeshCoverageWorkspace(attributed: true)
        let view = try #require(workspace.view)
        let item = try #require(view.viewport.items.first)
        let asset = try #require(view.document.document.authoredMeshAssets[item.mesh.identity])
        var draft = MeshOperationDraft(
            sourceID: asset.id,
            contentIdentity: asset.contentIdentity,
            occurrenceID: item.id,
            unit: .millimeter
        )
        configure(&draft, asset)
        _ = try await workspace.commit(try draft.request(from: view))
        let committedView = try #require(workspace.view)
        let committed = try #require(committedView.document.document.authoredMeshAssets[asset.id])
        return (asset, committed)
    }

    private func measuredSolidVolume(in document: DesignDocument) throws -> Double {
        try MeasurementService().measure(
            document: document,
            ruler: .standard(for: .millimeter)
        ).totals.solidVolumeCubicMeters
    }

    private func makeModelingDraft(
        _ kind: ModelingOperationDraft.Kind,
        targets: [SelectionTarget] = []
    ) -> ModelingOperationDraft {
        ModelingOperationDraft(
            kind: kind,
            selection: SelectionModel(selectedTargets: targets),
            ruler: .standard(for: .millimeter)
        )
    }

    private func addProfile(
        to document: inout DesignDocument,
        z: Double
    ) throws -> (feature: FeatureID, target: SelectionTarget) {
        let feature = try document.createRectangleSketchFromCorners(
            name: "Profile",
            plane: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: z), normal: .unitZ)),
            firstCorner: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            oppositeCorner: SketchPoint(x: .length(0.004, .meter), y: .length(0.012, .meter))
        )
        let node = try #require(document.productMetadata.sceneNodes.values.first {
            $0.reference == .sketch(feature)
        })
        return (feature, SelectionTarget(sceneNodeID: node.id))
    }

    private func addBooleanBody(
        to document: inout DesignDocument,
        name: String,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double
    ) throws -> FeatureID {
        let sketch = try document.createRectangleSketchFromCorners(
            name: "\(name) Sketch",
            plane: .xy,
            firstCorner: SketchPoint(x: .length(minX, .millimeter), y: .length(minY, .millimeter)),
            oppositeCorner: SketchPoint(x: .length(maxX, .millimeter), y: .length(maxY, .millimeter))
        )
        return try document.extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketch),
            distance: .length(10, .millimeter),
            direction: .normal
        )
    }

    @MainActor
    private func makeMeshCoverageWorkspace(
        attributed: Bool = false
    ) async throws -> ProjectWorkspace {
        var builder = MeshSourceBuilder()
        let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
        let second = try builder.addVertex(GeometryPoint3D(x: 0.01, y: 0, z: 0))
        let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 0.01, z: 0))
        _ = try builder.addFace(vertexIDs: [first, second, third])
        if attributed {
            // The CAD route converts with a dense vertex normal layer.
            try builder.setAttribute(
                GeometryAttributeLayer(
                    descriptor: GeometryAttributeDescriptor(
                        id: "cad.normal",
                        name: "Normal",
                        domain: .vertex,
                        valueType: .vector3,
                        interpolation: .linear
                    ),
                    values: .vector3(GeometryBuffer([
                        GeometryPoint3D(x: 0, y: 0, z: 1),
                        GeometryPoint3D(x: 0, y: 0, z: 1),
                        GeometryPoint3D(x: 0, y: 0, z: 1),
                    ]))
                )
            )
        }
        let asset = try AuthoredMeshAsset(source: builder.build(), provenance: .created)
        var document = DesignDocument.empty()
        document.authoredMeshAssets[asset.id] = asset
        let representationID = GeometryRepresentationID()
        _ = try document.productMetadata.appendSceneNodeToFirstRoot(
            name: "Mesh",
            reference: .authoredMesh(asset.id),
            object: ObjectDescriptor(
                category: .body,
                geometryRole: .mesh,
                geometryRepresentations: GeometryRepresentationSet(
                    representations: [
                        representationID: GeometryRepresentation(
                            id: representationID,
                            source: .authoredMesh(asset.id)
                        ),
                    ],
                    selection: GeometryRepresentationSelection(
                        modeling: representationID,
                        presentation: representationID
                    )
                )
            )
        )
        let controller = try ProjectController(
            document: document,
            evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
            projector: DesignDocumentProjectBridge()
        )
        let workspace = ProjectWorkspace(project: controller)
        _ = try await workspace.evaluate()
        return workspace
    }
}
