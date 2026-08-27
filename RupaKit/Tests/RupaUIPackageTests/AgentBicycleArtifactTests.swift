import CoreGraphics
import Foundation
import ImageIO
import RupaAgentProtocol
import RupaAgentRuntime
import RupaAutomation
import RupaCore
import RupaCoreTypes
@testable import RupaGeometry
import RupaKit
import RupaProject
import RupaProjectModel
import RupaProjectPackage
import RupaRendering
import RupaViewportScene
import Testing
import UniformTypeIdentifiers

@MainActor
@Test(.timeLimit(.minutes(5)))
func agentBuildsEditsPersistsAndRendersBicycleArtifact() async throws {
    let project = try ProjectController(
        document: BicycleArtifact.document(),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let workspace = ProjectWorkspace(project: project)
    _ = try await workspace.evaluate()
    let controller = ProjectAgentCommandController()
    let sessionID = UUID(uuidString: "D3B981EC-DBB1-49F4-9607-25D123CB87CF")!
    try await controller.register(workspace: workspace, id: sessionID)
    let harness = BicycleArtifact.AgentHarness(
        controller: controller,
        workspace: workspace,
        sessionID: sessionID
    )

    let creationBase = try #require(workspace.view)
    let creation = await harness.send(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: try BicycleArtifact.parts.map { try $0.creationCommand() },
                expectedGeneration: creationBase.documentGeneration,
                expectedTransactionRevision: creationBase.transactionRevision,
                expectedWorkspaceRevision: creationBase.workspaceState.revision
            )
        )
    )
    guard case .batch(let creationResult) = creation,
          creationResult.results.count == BicycleArtifact.parts.count else {
        Issue.record("Expected one Agent CAD batch result for every bicycle part.")
        return
    }
    let featureIDs = try creationResult.results.map { try #require($0.primaryFeatureID) }

    let topology = await harness.send(
        .topologySummary(
            sessionID: sessionID,
            expectedGeneration: try #require(workspace.view).documentGeneration
        )
    )
    guard case .topologySummary(let topologyResult) = topology else {
        Issue.record("Expected Agent topology inspection to enumerate the bicycle assembly.")
        return
    }
    var bodies: [BicycleArtifact.Body] = []
    for (part, featureID) in zip(BicycleArtifact.parts, featureIDs) {
        let bodyEntry = try #require(topologyResult.entries.first {
            $0.kind == .body && $0.sourceFeatureID == featureID.description
        })
        let sceneNodeUUID = try #require(bodyEntry.sceneNodeID.flatMap(UUID.init(uuidString:)))
        bodies.append(
            BicycleArtifact.Body(
                part: part,
                featureID: featureID,
                sceneNodeID: SceneNodeID(sceneNodeUUID),
                sourceID: GeometrySourceID(rawValue: "mesh.bicycle.\(part.key)"),
                representationID: GeometryRepresentationID(
                    rawValue: "representation.bicycle.\(part.key)"
                )
            )
        )
    }
    let transformBase = try #require(workspace.view)
    let transform = await harness.send(
        .executeBatch(
            sessionID: sessionID,
            batch: AutomationBatch(
                commands: try bodies.map {
                    .setSceneNodeTransform(
                        id: $0.sceneNodeID,
                        localTransform: try $0.part.transform()
                    )
                },
                expectedGeneration: transformBase.documentGeneration,
                expectedTransactionRevision: transformBase.transactionRevision,
                expectedWorkspaceRevision: transformBase.workspaceState.revision
            )
        )
    )
    guard case .batch(let transformResult) = transform,
          transformResult.didMutate else {
        Issue.record("Expected the Agent bicycle placement batch to publish.")
        return
    }

    #expect(bodies.count == BicycleArtifact.parts.count)
    #expect(Set(bodies.map(\.featureID)).count == bodies.count)
    #expect(Set(bodies.map(\.sceneNodeID)).count == bodies.count)
    let cadFingerprintBeforeMakeEditable = try #require(workspace.view)
        .document.document.cadDocument.sourceFingerprint(tolerance: .standard)

    var makeEditableResults: [GeometrySourceID: AgentMakeEditableResult] = [:]
    for body in bodies {
        let response = await harness.send(
            .makeEditable(
                AgentMakeEditableRequest(
                    sessionID: sessionID,
                    expectedGeneration: try #require(workspace.view).documentGeneration,
                    sceneNodeID: body.sceneNodeID,
                    authoredMeshSourceID: body.sourceID,
                    authoredMeshRepresentationID: body.representationID,
                    switchesPresentationSelection: true,
                    name: "agent.bicycle.make-editable.\(body.part.key)"
                )
            )
        )
        guard case .makeEditable(let result) = response else {
            Issue.record("Expected Agent Make Editable for \(body.part.key) to succeed.")
            return
        }
        #expect(result.authoredMeshSourceID == body.sourceID)
        #expect(result.authoredMeshRepresentationID == body.representationID)
        #expect(result.switchedPresentationSelection)
        #expect(result.copyTelemetry.didCopy == false)
        makeEditableResults[body.sourceID] = result
    }

    let editableView = try #require(workspace.view)
    #expect(editableView.document.document.authoredMeshAssets.count == bodies.count)
    #expect(try editableView.document.document.cadDocument.sourceFingerprint(
        tolerance: .standard
    ) == cadFingerprintBeforeMakeEditable)
    for body in bodies {
        try BicycleArtifact.expectAuthorityPairing(
            body,
            in: editableView.document.document,
            makeEditableResult: try #require(makeEditableResults[body.sourceID])
        )
    }

    let representative = try #require(bodies.first { $0.part.key == "rear-wheel" })
    let catalogResponse = await harness.send(
        .meshCatalog(
            AgentMeshCatalogRequest(
                sessionID: sessionID,
                expectedGeneration: editableView.documentGeneration,
                limits: ProjectMeshReadLimits(maxSources: bodies.count)
            )
        )
    )
    guard case .meshCatalog(let catalogResult) = catalogResponse else {
        Issue.record("Expected the Agent Mesh catalog to expose all bicycle assets.")
        return
    }
    #expect(catalogResult.catalog.sources.count == bodies.count)
    let representativeCatalog = try #require(
        catalogResult.catalog.source(for: representative.sourceID)
    )

    let pageResponse = await harness.send(
        .meshPage(
            AgentMeshPageRequest(
                sessionID: sessionID,
                expectedGeneration: editableView.documentGeneration,
                handle: representativeCatalog.handle,
                domain: .vertex,
                limits: ProjectMeshReadLimits(maxPageRecords: 1)
            )
        )
    )
    guard case .meshPage(let pageResult) = pageResponse,
          case .vertex(let vertex) = try #require(pageResult.page.records.first) else {
        Issue.record("Expected one representative bicycle Mesh vertex from the Agent page route.")
        return
    }

    let neighborhoodResponse = await harness.send(
        .meshNeighborhood(
            AgentMeshNeighborhoodRequest(
                sessionID: sessionID,
                expectedGeneration: editableView.documentGeneration,
                handle: representativeCatalog.handle,
                origin: .vertex(vertex.id),
                depth: 0,
                limits: .standard
            )
        )
    )
    guard case .meshNeighborhood(let neighborhoodResult) = neighborhoodResponse else {
        if case .failure(let error) = neighborhoodResponse {
            Issue.record(
                "Expected representative bicycle Mesh neighborhood inspection to succeed: \(error.code.rawValue): \(error.message)"
            )
        } else {
            Issue.record("Expected representative bicycle Mesh neighborhood inspection to succeed.")
        }
        return
    }
    #expect(neighborhoodResult.neighborhood.records.first?.distance == 0)

    let editedPosition = GeometryPoint3D(
        x: vertex.position.x,
        y: vertex.position.y + 0.12,
        z: vertex.position.z + 0.04
    )
    let editPlan = try MeshEditPlan(
        steps: [
            MeshEditStep(
                id: MeshEditStepID("raise-rear-wheel-vertex"),
                operation: .primitive(
                    .setVertexPositions([
                        try MeshVertexPositionEdit(
                            vertexID: vertex.id,
                            position: editedPosition
                        ),
                    ])
                )
            ),
        ]
    )
    let beforePreviewView = try #require(workspace.view)
    let beforePreviewAssets = beforePreviewView.document.document.authoredMeshAssets
    let previewResponse = await harness.send(
        .meshEdit(
            AgentMeshEditRequest(
                sessionID: sessionID,
                expectedGeneration: beforePreviewView.documentGeneration,
                handle: representativeCatalog.handle,
                plan: editPlan,
                mode: .preview,
                name: "agent.bicycle.mesh.preview"
            )
        )
    )
    guard case .meshEditPreview(let previewResult) = previewResponse else {
        Issue.record("Expected the bicycle Mesh preview route to succeed.")
        return
    }
    #expect(previewResult.didMutate)
    let afterPreviewView = try #require(workspace.view)
    #expect(afterPreviewView.documentGeneration == beforePreviewView.documentGeneration)
    #expect(afterPreviewView.transactionRevision == beforePreviewView.transactionRevision)
    #expect(afterPreviewView.publicationSequence == beforePreviewView.publicationSequence)
    #expect(afterPreviewView.document.document.authoredMeshAssets == beforePreviewAssets)

    let commitResponse = await harness.send(
        .meshEdit(
            AgentMeshEditRequest(
                sessionID: sessionID,
                expectedGeneration: beforePreviewView.documentGeneration,
                handle: representativeCatalog.handle,
                plan: editPlan,
                mode: .commit,
                name: "agent.bicycle.mesh.commit"
            )
        )
    )
    guard case .meshEditCommit(let commitResult) = commitResponse else {
        Issue.record("Expected the bicycle Mesh commit route to publish.")
        return
    }
    #expect(commitResult.didMutate)
    #expect(commitResult.previousContentIdentity == representativeCatalog.contentIdentity)
    #expect(commitResult.contentIdentity != commitResult.previousContentIdentity)
    #expect(commitResult.coordinates.transactionRevision.value
        == beforePreviewView.transactionRevision.value + 1)
    let editCopyEvents = commitResult.receipt.telemetry.events.filter {
        $0.reason == .sourceEdit
    }
    #expect(editCopyEvents.count == 1)
    #expect(commitResult.receipt.telemetry.copiedBytes > 0)

    let committedView = try #require(workspace.view)
    for body in bodies {
        let before = try #require(beforePreviewAssets[body.sourceID])
        let after = try #require(
            committedView.document.document.authoredMeshAssets[body.sourceID]
        )
        if body.sourceID == representative.sourceID {
            #expect(after.contentIdentity == commitResult.contentIdentity)
            #expect(after != before)
        } else {
            #expect(after == before)
        }
        try BicycleArtifact.expectAuthorityPairing(
            body,
            in: committedView.document.document,
            makeEditableResult: try #require(makeEditableResults[body.sourceID])
        )
    }

    let beforeUnsupportedSave = try #require(workspace.view)
    let unsupportedSaveResponse = await harness.send(
        .save(
            sessionID: sessionID,
            expectedGeneration: beforeUnsupportedSave.documentGeneration
        )
    )
    guard case .failure(let unsupportedSaveError) = unsupportedSaveResponse else {
        Issue.record("Expected application-owned save to remain unsupported through Agent routing.")
        return
    }
    #expect(unsupportedSaveError.code == .commandUnsupported)
    #expect(try #require(workspace.view).publicationSequence
        == beforeUnsupportedSave.publicationSequence)

    let artifactLocation = try BicycleArtifact.artifactLocation()
    defer {
        if artifactLocation.removesOnExit {
            do {
                try FileManager.default.removeItem(at: artifactLocation.url)
            } catch {
                Issue.record("Temporary bicycle artifact cleanup failed: \(error).")
            }
        }
    }
    let artifactDirectory = artifactLocation.url
    let packageURL = artifactDirectory.appendingPathComponent("agent-bicycle.rupa")
    let pngURL = artifactDirectory.appendingPathComponent("agent-bicycle.png")
    let reportURL = artifactDirectory.appendingPathComponent("agent-bicycle-report.json")
    let transcriptURL = artifactDirectory.appendingPathComponent(
        "agent-bicycle-agent-transcript.json"
    )
    try BicycleArtifact.removeExistingArtifacts([
        packageURL,
        pngURL,
        reportURL,
        transcriptURL,
    ])
    let savedView = try await workspace.save(to: packageURL)
    #expect(savedView.isDirty == false)

    let packageData = try Data(contentsOf: packageURL, options: [.alwaysMapped])
    #expect(packageData.isEmpty == false)
    #expect(packageData.count < 50 * 1_024 * 1_024)
    #expect(packageData.range(of: Data("source/rupa.json".utf8)) == nil)
    #expect(packageData.range(of: Data("source/cad.json".utf8)) != nil)
    #expect(packageData.range(of: Data("source/mesh-assets.json".utf8)) != nil)
    let storedPackage = try ProjectPackageStore().load(from: packageURL)
    #expect(storedPackage.cadSource != nil)
    #expect(storedPackage.authoredMeshAssets.count == bodies.count)
    #expect(Set(storedPackage.authoredMeshAssets.keys) == Set(bodies.map(\.sourceID)))

    let loadedProject = try ProjectController(
        document: BicycleArtifact.document(named: "Bicycle Load Target"),
        evaluatorPreparer: DefaultDesignDocumentProjectEvaluatorFactory(),
        projector: DesignDocumentProjectBridge()
    )
    let loadedWorkspace = ProjectWorkspace(project: loadedProject)
    _ = try await loadedWorkspace.evaluate()
    let loadedView = try await loadedWorkspace.load(from: packageURL)
    let loadedState = try await loadedProject.currentState()
    #expect(loadedView.projectID == committedView.projectID)
    #expect(loadedView.isDirty == false)
    #expect(loadedState.evaluation.id.purpose == .presentation)
    #expect(loadedState.package.authoredMeshAssets.count == bodies.count)
    #expect(try loadedState.document.cadDocument.sourceFingerprint(tolerance: .standard)
        == cadFingerprintBeforeMakeEditable)
    for body in bodies {
        try BicycleArtifact.expectAuthorityPairing(
            body,
            in: loadedState.document,
            makeEditableResult: try #require(makeEditableResults[body.sourceID])
        )
        #expect(loadedState.document.authoredMeshAssets[body.sourceID]?.contentIdentity
            == committedView.document.document.authoredMeshAssets[body.sourceID]?.contentIdentity)
    }

    let scene = try UniversalViewportSceneBuilder().build(
        from: loadedState.evaluation,
        project: loadedState.evaluationSource
    )
    #expect(scene == loadedView.viewport)
    #expect(scene.items.count == bodies.count)
    #expect(scene.items.allSatisfy {
        if case .authoredMesh = $0.sourceReference { return true }
        return false
    })

    var everyPresentationBufferShared = true
    for item in scene.items {
        guard case .authoredMesh(let sourceID) = item.sourceReference,
              let asset = loadedState.document.authoredMeshAssets[sourceID] else {
            Issue.record("Expected each loaded bicycle presentation item to resolve to Authored Mesh.")
            return
        }
        let isShared = BicycleArtifact.everyBufferIsShared(asset.source, item.mesh)
        everyPresentationBufferShared = everyPresentationBufferShared && isShared
        #expect(isShared)
        #expect(item.copyTelemetry.didCopy == false)
    }
    #expect(scene.copyTelemetry.didCopy == false)

    let renderer = MeshSourcePresentationRenderer()
    let renderPlan = try renderer.makePlan(for: scene)
    var triangles: [MeshSourcePresentationTriangle] = []
    try renderer.render(plan: renderPlan) { triangles.append($0) }
    #expect(renderPlan.itemCount == bodies.count)
    #expect(renderPlan.triangleCount == triangles.count)
    #expect(triangles.isEmpty == false)
    let triangleCounts = BicycleArtifact.triangleCountsBySource(triangles)
    for body in bodies {
        #expect((triangleCounts[body.sourceID] ?? 0) > 0)
    }

    let representativeItem = try #require(scene.items.first {
        $0.sourceReference == .authoredMesh(representative.sourceID)
    })
    let expectedEditedWorldPosition = try representativeItem.worldTransform.applying(
        to: editedPosition
    )
    #expect(triangles.contains {
        BicycleArtifact.triangle($0, contains: vertex.id, at: expectedEditedWorldPosition)
    })

    let pngData = try BicycleArtifact.pngData(
        triangles: triangles,
        bodyBySourceID: Dictionary(uniqueKeysWithValues: bodies.map { ($0.sourceID, $0) })
    )
    let secondPNGData = try BicycleArtifact.pngData(
        triangles: triangles,
        bodyBySourceID: Dictionary(uniqueKeysWithValues: bodies.map { ($0.sourceID, $0) })
    )
    #expect(pngData == secondPNGData)
    #expect(pngData.isEmpty == false)
    #expect(pngData.count < 5 * 1_024 * 1_024)
    let imageSource = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    #expect(image.width == BicycleArtifact.imageWidth)
    #expect(image.height == BicycleArtifact.imageHeight)
    try pngData.write(to: pngURL, options: .atomic)

    let packageFingerprint = try ContentFingerprint.sha256(
        algorithm: "sha256-agent-bicycle-package-v1",
        data: packageData
    )
    let pngFingerprint = try ContentFingerprint.sha256(
        algorithm: "sha256-agent-bicycle-png-v1",
        data: pngData
    )
    let report = BicycleArtifact.Report(
        projectID: loadedView.projectID.rawValue,
        bodyCount: bodies.count,
        authoredMeshCount: loadedState.document.authoredMeshAssets.count,
        rendererItemCount: renderPlan.itemCount,
        triangleCount: triangles.count,
        packageByteCount: packageData.count,
        packageSHA256: packageFingerprint.value,
        pngByteCount: pngData.count,
        pngSHA256: pngFingerprint.value,
        representativeSourceID: representative.sourceID.rawValue,
        representativeIdentityBeforeEdit: commitResult.previousContentIdentity.fingerprint.value,
        representativeIdentityAfterEdit: commitResult.contentIdentity.fingerprint.value,
        previewPublished: false,
        editCopiedBytes: commitResult.receipt.telemetry.copiedBytes,
        editCopyEventCount: editCopyEvents.count,
        everyPresentationBufferShared: everyPresentationBufferShared,
        agentSaveUnsupported: unsupportedSaveError.code == .commandUnsupported,
        bodies: bodies.map { body in
            BicycleArtifact.BodyReport(
                key: body.part.key,
                name: body.part.name,
                featureID: body.featureID.description,
                sceneNodeID: body.sceneNodeID.description,
                authoredMeshSourceID: body.sourceID.rawValue,
                authoredMeshRepresentationID: body.representationID.rawValue,
                contentIdentity: loadedState.document.authoredMeshAssets[body.sourceID]?
                    .contentIdentity.fingerprint.value ?? "",
                triangleCount: triangleCounts[body.sourceID] ?? 0
            )
        }
    )
    try BicycleArtifact.writeJSON(report, to: reportURL)
    try BicycleArtifact.writeJSON(harness.transcript, to: transcriptURL)
}

private enum BicycleArtifact {
    static let imageWidth = 1_200
    static let imageHeight = 800

    struct Part: Sendable {
        enum Shape: Sendable {
            case circle(radius: Double, depth: Double)
            case tube(length: Double, thickness: Double, depth: Double)
        }

        let key: String
        let name: String
        let shape: Shape
        let centerX: Double
        let centerY: Double
        let centerZ: Double
        let angle: Double

        func creationCommand() throws -> AutomationCommand {
            switch shape {
            case .circle(let radius, let depth):
                return .createExtrudedCircle(
                    name: name,
                    plane: nil,
                    center: SketchPoint(
                        x: .length(0, .meter),
                        y: .length(0, .meter)
                    ),
                    radius: .length(radius, .meter),
                    depth: .length(depth, .meter),
                    direction: .normal
                )
            case .tube(let length, let thickness, let depth):
                return .createExtrudedRectangle(
                    name: name,
                    plane: nil,
                    width: .length(length, .meter),
                    height: .length(thickness, .meter),
                    depth: .length(depth, .meter),
                    direction: .normal
                )
            }
        }

        func transform() throws -> Transform3D {
            let cosine = cos(angle)
            let sine = sin(angle)
            return Transform3D(
                matrix: try Matrix4x4(values: [
                    cosine, -sine, 0, centerX,
                    sine, cosine, 0, centerY,
                    0, 0, 1, centerZ,
                    0, 0, 0, 1,
                ])
            )
        }
    }

    struct Body: Sendable {
        let part: Part
        let featureID: FeatureID
        let sceneNodeID: SceneNodeID
        let sourceID: GeometrySourceID
        let representationID: GeometryRepresentationID
    }

    struct TranscriptEntry: Codable, Sendable {
        let sequence: Int
        let method: String
        let status: String
        let documentGeneration: UInt64?
        let transactionRevision: UInt64?
        let publicationSequence: UInt64?
    }

    struct BodyReport: Codable, Sendable {
        let key: String
        let name: String
        let featureID: String
        let sceneNodeID: String
        let authoredMeshSourceID: String
        let authoredMeshRepresentationID: String
        let contentIdentity: String
        let triangleCount: Int
    }

    struct ArtifactLocation: Sendable {
        let url: URL
        let removesOnExit: Bool
    }

    struct Report: Codable, Sendable {
        let projectID: String
        let bodyCount: Int
        let authoredMeshCount: Int
        let rendererItemCount: Int
        let triangleCount: Int
        let packageByteCount: Int
        let packageSHA256: String
        let pngByteCount: Int
        let pngSHA256: String
        let representativeSourceID: String
        let representativeIdentityBeforeEdit: String
        let representativeIdentityAfterEdit: String
        let previewPublished: Bool
        let editCopiedBytes: UInt64
        let editCopyEventCount: Int
        let everyPresentationBufferShared: Bool
        let agentSaveUnsupported: Bool
        let bodies: [BodyReport]
    }

    @MainActor
    final class AgentHarness {
        let controller: ProjectAgentCommandController
        let workspace: ProjectWorkspace
        let sessionID: UUID
        private(set) var transcript: [TranscriptEntry] = []

        init(
            controller: ProjectAgentCommandController,
            workspace: ProjectWorkspace,
            sessionID: UUID
        ) {
            self.controller = controller
            self.workspace = workspace
            self.sessionID = sessionID
        }

        func send(_ request: AgentRequest) async -> AgentResponse {
            let response = await controller.handle(request)
            let view = workspace.view
            transcript.append(
                TranscriptEntry(
                    sequence: transcript.count + 1,
                    method: request.methodName,
                    status: status(response),
                    documentGeneration: view?.documentGeneration.value,
                    transactionRevision: view?.transactionRevision.value,
                    publicationSequence: view?.publicationSequence
                )
            )
            return response
        }

        private func status(_ response: AgentResponse) -> String {
            if case .failure(let error) = response {
                return "failure:\(error.code.rawValue)"
            }
            if case .committedMutation = response {
                return "committed-must-not-retry"
            }
            return "success"
        }
    }

    static let parts: [Part] = {
        let rear = (-1.4, 0.0)
        let front = (1.4, 0.0)
        let crank = (0.0, -0.05)
        let seat = (-0.15, 0.92)
        let steering = (0.92, 0.84)
        return [
            Part(
                key: "rear-wheel",
                name: "Rear Wheel",
                shape: .circle(radius: 0.72, depth: 0.08),
                centerX: rear.0,
                centerY: rear.1,
                centerZ: -0.08,
                angle: 0
            ),
            Part(
                key: "front-wheel",
                name: "Front Wheel",
                shape: .circle(radius: 0.72, depth: 0.08),
                centerX: front.0,
                centerY: front.1,
                centerZ: -0.08,
                angle: 0
            ),
            tube("chainstay", "Chainstay", rear, crank, 0.11, 0.10, 0.03),
            tube("seat-tube", "Seat Tube", crank, seat, 0.12, 0.10, 0.04),
            tube("top-tube", "Top Tube", seat, steering, 0.12, 0.10, 0.04),
            tube("down-tube", "Down Tube", steering, crank, 0.13, 0.11, 0.05),
            tube("fork", "Front Fork", steering, front, 0.10, 0.10, 0.04),
            tube("seat", "Seat", (-0.48, 0.93), (0.16, 0.93), 0.16, 0.12, 0.08),
            tube("handlebar", "Handlebar", (0.76, 0.95), (1.28, 0.95), 0.11, 0.12, 0.08),
            Part(
                key: "crank",
                name: "Crank",
                shape: .circle(radius: 0.19, depth: 0.14),
                centerX: crank.0,
                centerY: crank.1,
                centerZ: 0.10,
                angle: 0
            ),
        ]
    }()

    static func document(named name: String = "Agent Bicycle") -> DesignDocument {
        var document = DesignDocument.empty(named: name)
        document.modelingSettings.tessellationOptions = .init(
            linearTolerance: 0.01,
            angularTolerance: 0.08
        )
        return document
    }

    static func tube(
        _ key: String,
        _ name: String,
        _ start: (Double, Double),
        _ end: (Double, Double),
        _ thickness: Double,
        _ depth: Double,
        _ centerZ: Double
    ) -> Part {
        let deltaX = end.0 - start.0
        let deltaY = end.1 - start.1
        return Part(
            key: key,
            name: name,
            shape: .tube(
                length: (deltaX * deltaX + deltaY * deltaY).squareRoot(),
                thickness: thickness,
                depth: depth
            ),
            centerX: (start.0 + end.0) / 2,
            centerY: (start.1 + end.1) / 2,
            centerZ: centerZ,
            angle: atan2(deltaY, deltaX)
        )
    }

    static func expectAuthorityPairing(
        _ body: Body,
        in document: DesignDocument,
        makeEditableResult: AgentMakeEditableResult
    ) throws {
        let object = try #require(document.productMetadata.sceneNodes[body.sceneNodeID]?.object)
        let selection = try #require(object.geometryRepresentations.selection)
        let modeling = try #require(
            object.geometryRepresentations.representations[selection.modeling]
        )
        let presentation = try #require(
            object.geometryRepresentations.representations[selection.presentation]
        )
        guard case .cad = modeling.source else {
            Issue.record("Expected \(body.part.key) modeling authority to remain CAD.")
            return
        }
        #expect(selection.modeling == makeEditableResult.sourceRepresentationID)
        #expect(selection.presentation == body.representationID)
        #expect(presentation.source == .authoredMesh(body.sourceID))
        let asset = try #require(document.authoredMeshAssets[body.sourceID])
        #expect(asset.provenance == makeEditableResult.provenance)
        #expect(asset.provenance == .derivedFromCAD(
            representationID: selection.modeling,
            sourceIdentity: makeEditableResult.cadSourceIdentity
        ))
    }

    static func everyBufferIsShared(_ source: MeshSource, _ presentation: MeshSource) -> Bool {
        guard source.vertexIDs.storage.chunkIdentities
                == presentation.vertexIDs.storage.chunkIdentities,
              source.vertexPositions.storage.chunkIdentities
                == presentation.vertexPositions.storage.chunkIdentities,
              source.edgeIDs.storage.chunkIdentities
                == presentation.edgeIDs.storage.chunkIdentities,
              source.edgeEndpoints.storage.chunkIdentities
                == presentation.edgeEndpoints.storage.chunkIdentities,
              source.faceIDs.storage.chunkIdentities
                == presentation.faceIDs.storage.chunkIdentities,
              source.faceCornerRanges.storage.chunkIdentities
                == presentation.faceCornerRanges.storage.chunkIdentities,
              source.cornerIDs.storage.chunkIdentities
                == presentation.cornerIDs.storage.chunkIdentities,
              source.cornerVertexIDs.storage.chunkIdentities
                == presentation.cornerVertexIDs.storage.chunkIdentities,
              source.cornerEdgeIDs.storage.chunkIdentities
                == presentation.cornerEdgeIDs.storage.chunkIdentities else {
            return false
        }
        let sourceLayers = source.attributes.sortedLayers()
        let presentationLayers = presentation.attributes.sortedLayers()
        guard sourceLayers.map(\.descriptor.id) == presentationLayers.map(\.descriptor.id) else {
            return false
        }
        return zip(sourceLayers, presentationLayers).allSatisfy { lhs, rhs in
            attributeStorageIsShared(lhs.values, rhs.values)
                && lhs.indices?.storage.chunkIdentities == rhs.indices?.storage.chunkIdentities
        }
    }

    static func attributeStorageIsShared(
        _ lhs: GeometryAttributeStorage,
        _ rhs: GeometryAttributeStorage
    ) -> Bool {
        switch (lhs, rhs) {
        case (.boolean(let left), .boolean(let right)):
            return left.storage.chunkIdentities == right.storage.chunkIdentities
        case (.int32(let left), .int32(let right)):
            return left.storage.chunkIdentities == right.storage.chunkIdentities
        case (.float32(let left), .float32(let right)):
            return left.storage.chunkIdentities == right.storage.chunkIdentities
        case (.float64(let left), .float64(let right)):
            return left.storage.chunkIdentities == right.storage.chunkIdentities
        case (.vector2(let left), .vector2(let right)):
            return left.storage.chunkIdentities == right.storage.chunkIdentities
        case (.vector3(let left), .vector3(let right)):
            return left.storage.chunkIdentities == right.storage.chunkIdentities
        case (.vector4(let left), .vector4(let right)):
            return left.storage.chunkIdentities == right.storage.chunkIdentities
        default:
            return false
        }
    }

    static func triangleCountsBySource(
        _ triangles: [MeshSourcePresentationTriangle]
    ) -> [GeometrySourceID: Int] {
        var result: [GeometrySourceID: Int] = [:]
        for triangle in triangles {
            guard case .authoredMesh(let sourceID) = triangle.sourceReference else {
                continue
            }
            result[sourceID, default: 0] += 1
        }
        return result
    }

    static func triangle(
        _ triangle: MeshSourcePresentationTriangle,
        contains vertexID: MeshVertexID,
        at position: GeometryPoint3D
    ) -> Bool {
        let candidates = [
            (triangle.firstVertexID, triangle.firstPosition),
            (triangle.secondVertexID, triangle.secondPosition),
            (triangle.thirdVertexID, triangle.thirdPosition),
        ]
        return candidates.contains { candidate in
            candidate.0 == vertexID
                && abs(candidate.1.x - position.x) < 1.0e-9
                && abs(candidate.1.y - position.y) < 1.0e-9
                && abs(candidate.1.z - position.z) < 1.0e-9
        }
    }

    static func artifactLocation() throws -> ArtifactLocation {
        let environment = ProcessInfo.processInfo.environment
        let url: URL
        let removesOnExit: Bool
        if let configured = environment["RUPA_BICYCLE_ARTIFACT_DIR"] {
            url = URL(fileURLWithPath: configured, isDirectory: true)
            removesOnExit = false
        } else {
            url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "rupa-agent-bicycle-artifact-\(UUID().uuidString)",
                isDirectory: true
            )
            removesOnExit = true
        }
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return ArtifactLocation(url: url, removesOnExit: removesOnExit)
    }

    static func removeExistingArtifacts(_ urls: [URL]) throws {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    static func pngData(
        triangles: [MeshSourcePresentationTriangle],
        bodyBySourceID: [GeometrySourceID: Body]
    ) throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw EditorError(code: .commandFailed, message: "PNG raster context creation failed.")
        }
        let points = triangles.flatMap { [$0.firstPosition, $0.secondPosition, $0.thirdPosition] }
        guard let minimumX = points.map(\.x).min(),
              let maximumX = points.map(\.x).max(),
              let minimumY = points.map(\.y).min(),
              let maximumY = points.map(\.y).max() else {
            throw EditorError(code: .commandFailed, message: "PNG rendering requires triangles.")
        }
        let padding = 70.0
        let spanX = max(maximumX - minimumX, 1.0e-9)
        let spanY = max(maximumY - minimumY, 1.0e-9)
        let scale = min(
            (Double(imageWidth) - padding * 2) / spanX,
            (Double(imageHeight) - padding * 2) / spanY
        )
        let offsetX = (Double(imageWidth) - spanX * scale) / 2 - minimumX * scale
        let offsetY = (Double(imageHeight) - spanY * scale) / 2 - minimumY * scale

        context.setAllowsAntialiasing(false)
        context.setShouldAntialias(false)
        context.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        let ordered = triangles.sorted { lhs, rhs in
            let leftZ = (lhs.firstPosition.z + lhs.secondPosition.z + lhs.thirdPosition.z) / 3
            let rightZ = (rhs.firstPosition.z + rhs.secondPosition.z + rhs.thirdPosition.z) / 3
            if leftZ != rightZ { return leftZ < rightZ }
            return sourceID(of: lhs)?.rawValue ?? "" < sourceID(of: rhs)?.rawValue ?? ""
        }
        for triangle in ordered {
            let sourceID = sourceID(of: triangle)
            let key = sourceID.flatMap { bodyBySourceID[$0]?.part.key } ?? ""
            context.setFillColor(color(for: key))
            context.beginPath()
            context.move(to: projected(triangle.firstPosition, scale, offsetX, offsetY))
            context.addLine(to: projected(triangle.secondPosition, scale, offsetX, offsetY))
            context.addLine(to: projected(triangle.thirdPosition, scale, offsetX, offsetY))
            context.closePath()
            context.fillPath()
        }
        guard let image = context.makeImage() else {
            throw EditorError(code: .commandFailed, message: "PNG raster image creation failed.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw EditorError(code: .commandFailed, message: "PNG destination creation failed.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EditorError(code: .commandFailed, message: "PNG encoding failed.")
        }
        return data as Data
    }

    static func sourceID(
        of triangle: MeshSourcePresentationTriangle
    ) -> GeometrySourceID? {
        if case .authoredMesh(let sourceID) = triangle.sourceReference {
            return sourceID
        }
        return nil
    }

    static func projected(
        _ point: GeometryPoint3D,
        _ scale: Double,
        _ offsetX: Double,
        _ offsetY: Double
    ) -> CGPoint {
        CGPoint(
            x: point.x * scale + offsetX,
            y: point.y * scale + offsetY
        )
    }

    static func color(for key: String) -> CGColor {
        switch key {
        case "rear-wheel", "front-wheel":
            CGColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        case "seat", "handlebar":
            CGColor(red: 0.91, green: 0.35, blue: 0.16, alpha: 1)
        case "crank":
            CGColor(red: 0.96, green: 0.66, blue: 0.12, alpha: 1)
        default:
            CGColor(red: 0.08, green: 0.55, blue: 0.62, alpha: 1)
        }
    }
}
