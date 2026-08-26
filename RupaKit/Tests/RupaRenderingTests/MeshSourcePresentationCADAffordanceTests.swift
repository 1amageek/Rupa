import Foundation
import SwiftCAD
import Testing
import RupaCore
import RupaCoreTypes
import RupaEvaluation
import RupaKit
import RupaProjectModel
import RupaViewportScene
@testable import RupaGeometry
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationCADAffordanceUsesBridgeSceneAndExactCADContext() throws {
    let fixture = try bridgeCADFixture()
    let item = try #require(fixture.scene.items.first)
    let initialSceneTelemetry = fixture.scene.copyTelemetry
    let initialItemTelemetry = item.copyTelemetry
    let initialChunkIdentities = sourceChunkIdentitySummary(item.mesh)
    let navigationNodeID = try #require(
        fixture.navigation.sceneNodeID(for: item.occurrenceID)
    )
    let node = try #require(fixture.document.productMetadata.sceneNodes[navigationNodeID])
    let presentation = try #require(
        node.object?.geometryRepresentations.representation(for: .presentation)
    )
    let outputFeatureID = try outputFeatureID(from: item)

    let availability = MeshSourcePresentationCADAffordanceResolver().resolve(
        item: item,
        navigation: fixture.navigation,
        document: fixture.document,
        generation: fixture.generation,
        cadInteraction: fixture.cadInteraction
    )
    guard case let .available(context) = availability else {
        Issue.record("The bridge-produced CAD body must resolve to an exact context.")
        return
    }

    let cadInteraction = try #require(fixture.cadInteraction)
    let matchingBodyIDs = cadInteraction.evaluatedDocument.subshapes.entries
        .compactMap { subshapeID, reference -> BodyID? in
            guard subshapeID.featureID == outputFeatureID,
                  case let .body(bodyID) = reference,
                  cadInteraction.evaluatedDocument.brep.bodies[bodyID] != nil else {
                return nil
            }
            return bodyID
        }
    guard matchingBodyIDs.count == 1, let expectedBodyID = matchingBodyIDs.first else {
        Issue.record("The bridge CAD evaluation must expose exactly one evaluated body for the selected feature.")
        return
    }
    #expect(context.occurrenceID == item.occurrenceID)
    #expect(context.sceneNodeID == navigationNodeID)
    #expect(context.featureID == outputFeatureID)
    #expect(context.bodyID == expectedBodyID)
    #expect(context.generation == fixture.generation)
    #expect(context.representationID == item.representationID)
    #expect(context.representationID == presentation.id)
    #expect(context.sourceReference == item.reference)
    #expect(cadInteraction.matches(document: fixture.document, generation: fixture.generation))
    #expect(fixture.scene.copyTelemetry == initialSceneTelemetry)
    #expect(item.copyTelemetry == initialItemTelemetry)
    #expect(sourceChunkIdentitySummary(item.mesh) == initialChunkIdentities)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationBridgeSnapshotsTraverseRenderPickAndCADGateWithoutCopies() throws {
    let fixtures = [try bridgeCADFixture(), try bridgeMixedMeshFixture()]
    let renderer: any MeshSourcePresentationRendering = MeshSourcePresentationRenderer()
    let picker: any MeshSourcePresentationPicking = MeshSourcePresentationPicker()
    let resolver = MeshSourcePresentationCADAffordanceResolver()

    for fixture in fixtures {
        let item = try #require(fixture.scene.items.first)
        let plan = try renderer.makePlan(for: fixture.scene)
        let index = try picker.makeIndex(
            for: fixture.scene,
            navigation: fixture.navigation
        )
        let initialSceneTelemetry = fixture.scene.copyTelemetry
        let initialItemTelemetry = item.copyTelemetry
        let initialChunkIdentities = sourceChunkIdentitySummary(item.mesh)
        let sceneNodeID = try #require(
            fixture.navigation.sceneNodeID(for: item.occurrenceID)
        )
        var renderedTriangleCount = 0

        try renderer.render(plan: plan) { triangle in
            #expect(triangle.occurrenceID == item.occurrenceID)
            #expect(triangle.sourceReference == item.reference)
            let identity = try index.identity(for: triangle.occurrenceID)
            let record = try picker.resolve(
                identity: identity,
                in: index,
                expectedSnapshotID: fixture.scene.snapshotID
            )
            #expect(record.snapshotID == fixture.scene.snapshotID)
            #expect(record.occurrenceID == triangle.occurrenceID)
            #expect(record.sceneNodeID == sceneNodeID)

            let availability = resolver.resolve(
                item: item,
                navigation: fixture.navigation,
                document: fixture.document,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
            if case .cad = item.reference {
                guard case let .available(context) = availability else {
                    Issue.record("The bridge CAD presentation must retain its exact affordance context through pick traversal.")
                    return
                }
                #expect(context.occurrenceID == record.occurrenceID)
                #expect(context.sceneNodeID == record.sceneNodeID)
                #expect(context.representationID == item.representationID)
                #expect(context.sourceReference == triangle.sourceReference)
            } else {
                #expect(unavailableReason(availability) == .nonCADPresentation)
            }
            renderedTriangleCount += 1
        }

        #expect(renderedTriangleCount == plan.triangleCount)
        #expect(fixture.scene.copyTelemetry == initialSceneTelemetry)
        #expect(item.copyTelemetry == initialItemTelemetry)
        #expect(sourceChunkIdentitySummary(item.mesh) == initialChunkIdentities)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationCADAffordanceDisablesMeshAndExternalPresentationWithoutCADSubstitution() throws {
    let fixture = try bridgeMixedMeshFixture()
    let item = try #require(fixture.scene.items.first)
    let initialSceneTelemetry = fixture.scene.copyTelemetry
    let initialItemTelemetry = item.copyTelemetry
    let initialChunkIdentities = sourceChunkIdentitySummary(item.mesh)
    let nodeID = try #require(fixture.navigation.sceneNodeID(for: item.occurrenceID))
    let node = try #require(fixture.document.productMetadata.sceneNodes[nodeID])
    let modelingSource = try #require(
        node.object?.geometryRepresentations.source(for: .modeling)
    )
    guard case .cad = modelingSource else {
        Issue.record("The mixed bridge fixture must retain CAD as its modeling source.")
        return
    }
    #expect(
        node.object?.geometryRepresentations.source(for: .presentation)
            == item.reference
    )
    guard case let .authoredMesh(sourceID) = item.reference else {
        Issue.record("The mixed bridge fixture must publish an authored Mesh presentation source.")
        return
    }
    let documentSource = try #require(
        fixture.document.authoredMeshAssets[sourceID]?.source
    )
    let projectedSource = try #require(
        fixture.projection.source.authoredMeshAssets[sourceID]?.source
    )
    let evaluatedOccurrence = try #require(
        fixture.evaluatedSnapshot.occurrences[item.occurrenceID]
    )
    expectSharedGeometryBuffers(documentSource, projectedSource)
    expectSharedGeometryBuffers(projectedSource, evaluatedOccurrence.mesh)
    expectSharedGeometryBuffers(evaluatedOccurrence.mesh, item.mesh)
    #expect(evaluatedOccurrence.copyTelemetry.didCopy == false)
    #expect(fixture.evaluatedSnapshot.copyTelemetry.didCopy == false)
    #expect(fixture.scene.copyTelemetry.didCopy == false)
    #expect(item.copyTelemetry.didCopy == false)

    let resolver = MeshSourcePresentationCADAffordanceResolver()
    #expect(
        unavailableReason(
            resolver.resolve(
                item: item,
                navigation: fixture.navigation,
                document: fixture.document,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .nonCADPresentation
    )

    let externalItem = replacingItem(
        item,
        reference: .external(
            providerID: "external",
            sourceID: "external.presentation",
            outputID: "external.output"
        )
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: externalItem,
                navigation: fixture.navigation,
                document: fixture.document,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .nonCADPresentation
    )
    #expect(fixture.scene.copyTelemetry == initialSceneTelemetry)
    #expect(item.copyTelemetry == initialItemTelemetry)
    #expect(sourceChunkIdentitySummary(item.mesh) == initialChunkIdentities)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationCADAffordanceReportsTypedNavigationAuthorityAndContextFailures() throws {
    let fixture = try bridgeCADFixture()
    let item = try #require(fixture.scene.items.first)
    let resolver = MeshSourcePresentationCADAffordanceResolver()
    let initialSceneTelemetry = fixture.scene.copyTelemetry
    let initialItemTelemetry = item.copyTelemetry
    let initialChunkIdentities = sourceChunkIdentitySummary(item.mesh)

    let emptyNavigation = try MeshSourcePresentationNavigationMap(mappings: [])
    #expect(
        unavailableReason(
            resolver.resolve(
                item: item,
                navigation: emptyNavigation,
                document: fixture.document,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .missingNavigation
    )

    let missingNodeNavigation = try MeshSourcePresentationNavigationMap(
        mappings: [
            (occurrenceID: item.occurrenceID, sceneNodeID: SceneNodeID()),
        ]
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: item,
                navigation: missingNodeNavigation,
                document: fixture.document,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .missingSceneNode
    )

    let mismatchedRepresentationItem = replacingItem(
        item,
        representationID: GeometryRepresentationID(rawValue: "presentation.mismatch")
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: mismatchedRepresentationItem,
                navigation: fixture.navigation,
                document: fixture.document,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .presentationSelectionMismatch
    )

    let sourceMismatch = GeometrySourceReference.cad(
        sourceID: "foreign.document",
        outputID: try outputFeatureID(from: item).description
    )
    let sourceMismatchDocument = try documentWithPresentationSource(
        fixture.document,
        item: item,
        source: sourceMismatch
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: replacingItem(item, reference: sourceMismatch),
                navigation: fixture.navigation,
                document: sourceMismatchDocument,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .sourceDocumentMismatch
    )

    let invalidOutput = GeometrySourceReference.cad(
        sourceID: fixture.document.id.description,
        outputID: "not-a-feature-uuid"
    )
    let invalidOutputDocument = try documentWithPresentationSource(
        fixture.document,
        item: item,
        source: invalidOutput
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: replacingItem(item, reference: invalidOutput),
                navigation: fixture.navigation,
                document: invalidOutputDocument,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .invalidOutputIdentifier
    )

    let missingFeature = GeometrySourceReference.cad(
        sourceID: fixture.document.id.description,
        outputID: UUID().uuidString
    )
    let missingFeatureDocument = try documentWithPresentationSource(
        fixture.document,
        item: item,
        source: missingFeature
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: replacingItem(item, reference: missingFeature),
                navigation: fixture.navigation,
                document: missingFeatureDocument,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .missingFeature
    )

    #expect(
        unavailableReason(
            resolver.resolve(
                item: item,
                navigation: fixture.navigation,
                document: fixture.document,
                generation: fixture.generation,
                cadInteraction: nil
            )
        ) == .missingCADInteractionContext
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: item,
                navigation: fixture.navigation,
                document: fixture.document,
                generation: try fixture.generation.advanced(),
                cadInteraction: fixture.cadInteraction
            )
        ) == .staleCADInteractionContext
    )

    let bodyFeatureID = try outputFeatureID(from: item)
    let bodylessFeatureID = try #require(
        fixture.document.cadDocument.designGraph.order.first {
            $0 != bodyFeatureID
        }
    )
    let bodylessReference = GeometrySourceReference.cad(
        sourceID: fixture.document.id.description,
        outputID: bodylessFeatureID.description
    )
    let bodylessDocument = try documentWithPresentationSource(
        fixture.document,
        item: item,
        source: bodylessReference
    )
    #expect(
        unavailableReason(
            resolver.resolve(
                item: replacingItem(item, reference: bodylessReference),
                navigation: fixture.navigation,
                document: bodylessDocument,
                generation: fixture.generation,
                cadInteraction: fixture.cadInteraction
            )
        ) == .missingEvaluatedBody
    )
    #expect(fixture.scene.copyTelemetry == initialSceneTelemetry)
    #expect(item.copyTelemetry == initialItemTelemetry)
    #expect(sourceChunkIdentitySummary(item.mesh) == initialChunkIdentities)
}

private struct BridgeFixture {
    let document: DesignDocument
    let projection: DesignDocumentProjectProjection
    let evaluatedSnapshot: EvaluatedProjectSnapshot
    let generation: DocumentGeneration
    let cadInteraction: DocumentEvaluationContext?
    let scene: UniversalViewportScene
    let navigation: MeshSourcePresentationNavigationMap
}

private enum BridgeFixtureError: Error {
    case missingEvaluation
    case missingItem
    case missingSceneNode
    case missingObject
    case missingPresentation
    case missingRepresentation
}

@MainActor
private func bridgeCADFixture() throws -> BridgeFixture {
    let session = EditorSession()
    _ = session.createDefaultExtrudedRectangle()
    guard session.currentEvaluation != nil else {
        throw BridgeFixtureError.missingEvaluation
    }
    return try evaluateBridge(
        document: session.document,
        generation: session.generation,
        revision: session.transactionRevision,
        cadInteraction: session.currentEvaluation
    )
}

@MainActor
private func bridgeMixedMeshFixture() throws -> BridgeFixture {
    let session = EditorSession()
    _ = session.createDefaultExtrudedRectangle()
    guard let bodyFeatureID = session.document.cadDocument.designGraph.order.last,
          let bodyEntry = session.document.productMetadata.sceneNodes.first(where: {
              $0.value.reference == .body(bodyFeatureID)
          }),
          var bodyObject = bodyEntry.value.object,
          let modeling = bodyObject.geometryRepresentations.representation(for: .modeling),
          session.currentEvaluation != nil else {
        throw BridgeFixtureError.missingSceneNode
    }

    let source = try bridgeTestMeshSource()
    let presentationID = GeometryRepresentationID(rawValue: "bridge.presentation.mesh")
    let presentationReference = GeometrySourceReference.authoredMesh(source.identity)
    var representations = bodyObject.geometryRepresentations
    representations.representations[presentationID] = GeometryRepresentation(
        id: presentationID,
        source: presentationReference
    )
    representations.selection = GeometryRepresentationSelection(
        modeling: modeling.id,
        presentation: presentationID
    )
    bodyObject.geometryRepresentations = representations
    var bodyNode = bodyEntry.value
    bodyNode.object = bodyObject

    var document = session.document
    document.authoredMeshAssets[source.identity] = try AuthoredMeshAsset(
        source: source,
        provenance: .created
    )
    document.productMetadata.sceneNodes[bodyEntry.key] = bodyNode
    return try evaluateBridge(
        document: document,
        generation: session.generation,
        revision: session.transactionRevision,
        cadInteraction: session.currentEvaluation
    )
}

@MainActor
private func evaluateBridge(
    document: DesignDocument,
    generation: DocumentGeneration,
    revision: DocumentTransactionRevision,
    cadInteraction: DocumentEvaluationContext?
) throws -> BridgeFixture {
    let bridge = DesignDocumentProjectBridge()
    let projection = try bridge.projection(for: document)
    let evaluator = try DefaultDesignDocumentProjectEvaluatorFactory().makeEvaluator(
        for: document,
        reusing: cadInteraction
    )
    let snapshot = try evaluator.evaluate(
        project: projection.source,
        purpose: .presentation,
        revision: revision
    )
    let scene = try UniversalViewportSceneBuilder().build(
        from: snapshot,
        project: projection.source
    )
    guard scene.items.isEmpty == false else {
        throw BridgeFixtureError.missingItem
    }
    let navigation = try MeshSourcePresentationNavigationMap(
        mappings: try scene.items.map { item in
            guard let sceneNodeID = projection.sceneNodeIDByOccurrenceID[item.occurrenceID] else {
                throw BridgeFixtureError.missingSceneNode
            }
            return (occurrenceID: item.occurrenceID, sceneNodeID: sceneNodeID)
        }
    )
    return BridgeFixture(
        document: document,
        projection: projection,
        evaluatedSnapshot: snapshot,
        generation: generation,
        cadInteraction: cadInteraction,
        scene: scene,
        navigation: navigation
    )
}

private func expectSharedGeometryBuffers(_ expected: MeshSource, _ actual: MeshSource) {
    #expect(expected.vertexIDs.storage.chunkIdentities == actual.vertexIDs.storage.chunkIdentities)
    #expect(expected.vertexIDs.storage.pageIdentities == actual.vertexIDs.storage.pageIdentities)
    #expect(expected.vertexPositions.storage.chunkIdentities == actual.vertexPositions.storage.chunkIdentities)
    #expect(expected.vertexPositions.storage.pageIdentities == actual.vertexPositions.storage.pageIdentities)
    #expect(expected.edgeIDs.storage.chunkIdentities == actual.edgeIDs.storage.chunkIdentities)
    #expect(expected.edgeIDs.storage.pageIdentities == actual.edgeIDs.storage.pageIdentities)
    #expect(expected.edgeEndpoints.storage.chunkIdentities == actual.edgeEndpoints.storage.chunkIdentities)
    #expect(expected.edgeEndpoints.storage.pageIdentities == actual.edgeEndpoints.storage.pageIdentities)
    #expect(expected.faceIDs.storage.chunkIdentities == actual.faceIDs.storage.chunkIdentities)
    #expect(expected.faceIDs.storage.pageIdentities == actual.faceIDs.storage.pageIdentities)
    #expect(expected.faceCornerRanges.storage.chunkIdentities == actual.faceCornerRanges.storage.chunkIdentities)
    #expect(expected.faceCornerRanges.storage.pageIdentities == actual.faceCornerRanges.storage.pageIdentities)
    #expect(expected.cornerIDs.storage.chunkIdentities == actual.cornerIDs.storage.chunkIdentities)
    #expect(expected.cornerIDs.storage.pageIdentities == actual.cornerIDs.storage.pageIdentities)
    #expect(expected.cornerVertexIDs.storage.chunkIdentities == actual.cornerVertexIDs.storage.chunkIdentities)
    #expect(expected.cornerVertexIDs.storage.pageIdentities == actual.cornerVertexIDs.storage.pageIdentities)
    #expect(expected.cornerEdgeIDs.storage.chunkIdentities == actual.cornerEdgeIDs.storage.chunkIdentities)
    #expect(expected.cornerEdgeIDs.storage.pageIdentities == actual.cornerEdgeIDs.storage.pageIdentities)
}

private func outputFeatureID(
    from item: UniversalViewportSceneItem
) throws -> FeatureID {
    guard case let .cad(_, outputID) = item.reference,
          let uuid = UUID(uuidString: outputID) else {
        throw BridgeFixtureError.missingRepresentation
    }
    return FeatureID(uuid)
}

private func documentWithPresentationSource(
    _ document: DesignDocument,
    item: UniversalViewportSceneItem,
    source: GeometrySourceReference
) throws -> DesignDocument {
    guard let sceneNodeID = document.productMetadata.sceneNodes.first(where: {
        $0.value.object?.geometryRepresentations.selection?.presentation == item.representationID
    })?.key,
          var sceneNode = document.productMetadata.sceneNodes[sceneNodeID],
          var object = sceneNode.object,
          object.geometryRepresentations.representations[item.representationID] != nil else {
        throw BridgeFixtureError.missingRepresentation
    }
    var representations = object.geometryRepresentations
    representations.representations[item.representationID] = GeometryRepresentation(
        id: item.representationID,
        source: source
    )
    object.geometryRepresentations = representations
    sceneNode.object = object
    var updated = document
    updated.productMetadata.sceneNodes[sceneNodeID] = sceneNode
    return updated
}

private func replacingItem(
    _ item: UniversalViewportSceneItem,
    representationID: GeometryRepresentationID? = nil,
    reference: GeometrySourceReference? = nil
) -> UniversalViewportSceneItem {
    UniversalViewportSceneItem(
        id: item.id,
        definitionID: item.definitionID,
        displayName: item.displayName,
        representationID: representationID ?? item.representationID,
        reference: reference ?? item.reference,
        mesh: item.mesh,
        copyTelemetry: item.copyTelemetry,
        worldTransform: item.worldTransform,
        worldBounds: item.worldBounds
    )
}

private func unavailableReason(
    _ availability: MeshSourcePresentationCADAffordanceAvailability
) -> MeshSourcePresentationCADAffordanceUnavailableReason? {
    guard case let .unavailable(reason) = availability else {
        return nil
    }
    return reason
}

private func bridgeTestMeshSource() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: GeometrySourceID(rawValue: "bridge.presentation.mesh"))
    try builder.reserveCapacity(vertexCount: 4, faceCount: 1, cornerCount: 4)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 1, y: 1, z: 0))
    let fourth = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third, fourth])
    return try builder.build()
}

private func sourceChunkIdentitySummary(_ source: MeshSource) -> [[ObjectIdentifier]] {
    [
        source.vertexIDs.storage.chunkIdentities,
        source.vertexPositions.storage.chunkIdentities,
        source.edgeIDs.storage.chunkIdentities,
        source.edgeEndpoints.storage.chunkIdentities,
        source.faceIDs.storage.chunkIdentities,
        source.faceCornerRanges.storage.chunkIdentities,
        source.cornerIDs.storage.chunkIdentities,
        source.cornerVertexIDs.storage.chunkIdentities,
        source.cornerEdgeIDs.storage.chunkIdentities,
    ]
}
