import Foundation
import RupaKit
import RupaCADIntegration
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func cadConversionReuseRemainsAdmittedAndSafeAcrossConcurrentEvaluators() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let document = session.document
    let project = try DesignDocumentProjectBridge().sourceModel(for: document)
    let evaluation = try #require(session.currentEvaluation)
    let cache = CADMeshSourceConversionCache()
    let references = project.objectDefinitions.values.compactMap {
        $0.representations.source(for: .presentation)
    }
    let configuration = CADGeometryEvaluationConfiguration(tolerance: document.modelingSettings.tolerance,
        tessellationOptions: try document.displayTessellationOptions())
    func provider() throws -> CADGeometrySourceProvider {
        let isolated = CADDocumentEvaluationCache()
        try isolated.seed(validatedDocument: evaluation.validatedDocument.validatedCADDocument,
            evaluatedDocument: evaluation.evaluatedDocument, sourceRevision: .init(1), configuration: configuration)
        var result = CADGeometrySourceProvider(document: document.cadDocument, configuration: configuration, cache: isolated)
        result.conversionCache = cache
        return result
    }
    let request = try GeometrySourceEvaluationRequest(references: references, sourceRevision: .init(1),
        purpose: .presentation, allowance: .init(.standard))
    let baseline = try provider().evaluate(request, in: project)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
            let evaluator = try provider()
            group.addTask {
                let result = try evaluator.evaluate(request, in: project)
                for reference in references {
                    #expect(result[reference]?.mesh == baseline[reference]?.mesh)
                    #expect(result[reference]?.copyTelemetry.didCopy == false)
                }
            }
        }
        try await group.waitForAll()
    }
    let refused = try GeometrySourceEvaluationRequest(references: references, sourceRevision: .init(1),
        purpose: .presentation, allowance: .exhausted)
    let error = #expect(throws: EvaluationError.self) { _ = try provider().evaluate(refused, in: project) }
    #expect(error?.code == .resourceExhausted)
    #expect(cache.snapshot().count == baseline.count)
    cache.replace(with: [:])
    #expect(cache.snapshot().isEmpty)
}

@Test(.timeLimit(.minutes(1)))
func designDocumentFactoryReusesOnlyUnchangedConversionsAcrossIsolatedEvaluators() throws {
    let session = EditorSession()
    let firstCommand = try #require(session.createDefaultExtrudedRectangle())
    let feature = try #require(firstCommand.primaryFeatureID)
    let factory = DefaultDesignDocumentProjectEvaluatorFactory()
    func evaluate() throws -> EvaluatedProjectSnapshot {
        let evaluator = try factory.makeEvaluator(for: session.document, reusing: session.currentEvaluation)
        // Distinct staged candidates may have the same proposed revision.
        // Conversion reuse must not share their transaction revision authority.
        return try evaluator.evaluate(project: DesignDocumentProjectBridge().sourceModel(for: session.document),
                                      purpose: .presentation, revision: .init(99))
    }
    let initial = try evaluate()
    let original = try #require(initial.occurrences.values.first)
    #expect(original.copyTelemetry.didCopy)
    let unchanged = try #require(evaluate().occurrences[original.occurrenceID])
    #expect(!unchanged.copyTelemetry.didCopy)
    #expect(unchanged.mesh.vertexPositions.storageIdentityToken === original.mesh.vertexPositions.storageIdentityToken)

    _ = try #require(session.createDefaultExtrudedRectangle())
    let added = try evaluate()
    #expect(added.occurrences.count == 2)
    #expect(added.occurrences[original.occurrenceID]?.copyTelemetry.didCopy == false)
    #expect(added.occurrences.values.filter { $0.copyTelemetry.didCopy }.count == 1)

    _ = try session.execute(.setExtrudeDistance(featureID: feature, distance: .length(0.37, .meter)))
    let changed = try evaluate()
    let replacement = try #require(changed.occurrences[original.occurrenceID])
    #expect(replacement.copyTelemetry.didCopy)
    #expect(replacement.mesh != original.mesh)
    #expect(changed.occurrences.values.filter { $0.copyTelemetry.didCopy }.count == 1)
}

@Test(.timeLimit(.minutes(1)))
func designDocumentBridgeProjectsSceneHierarchyAndCADReferences() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let bridge = DesignDocumentProjectBridge()
    let projection = try bridge.projection(for: session.document)
    let project = projection.source

    #expect(project.id.rawValue == "project.\(session.document.id.description)")
    #expect(project.name == session.document.cadDocument.metadata.name)
    #expect(project.rootOccurrenceIDs.count == session.document.productMetadata.rootSceneNodeIDs.count)
    #expect(project.objectDefinitions.count == session.document.productMetadata.sceneNodes.count)
    #expect(project.occurrences.count == session.document.productMetadata.sceneNodes.count)
    #expect(
        Set(projection.sceneNodeIDByOccurrenceID.values)
            == Set(session.document.productMetadata.sceneNodes.keys)
    )

    let cadDefinitions = project.objectDefinitions.values.compactMap { definition -> GeometrySourceReference? in
        definition.representations.source(for: .modeling)
    }
    #expect(cadDefinitions.contains { reference in
        guard case .cad(let sourceID, let outputID) = reference else {
            return false
        }
        return sourceID == session.document.id.description
            && UUID(uuidString: outputID) != nil
    })
}

@Test(.timeLimit(.minutes(1)))
func designDocumentBridgeFeedsCADEvaluationThroughUniversalProjectModel() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let bridge = DesignDocumentProjectBridge()
    let project = try bridge.sourceModel(for: session.document)
    let evaluator = try DefaultDesignDocumentProjectEvaluatorFactory()
        .makeEvaluator(
            for: session.document,
            reusing: session.currentEvaluation
        )
    let snapshot = try evaluator.evaluate(
        project: project,
        purpose: .presentation,
        revision: session.transactionRevision
    )

    #expect(snapshot.occurrences.values.contains { occurrence in
        occurrence.reference.providerID == CADGeometrySourceProvider.identifier
            && occurrence.mesh.faceIDs.count > 0
    })
}

@Test(.timeLimit(.minutes(1)))
func designDocumentBridgeProjectsAllRepresentationsAndAuthoredMeshAssets() throws {
    let session = EditorSession()
    let commandResult = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(commandResult.primaryFeatureID)
    var document = session.document
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(object.geometryRepresentations.selection?.modeling)
    let mesh = try bridgeTriangleMesh()
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID = "representation.presentation-mesh"
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshRepresentationID] = GeometryRepresentation(
        id: meshRepresentationID,
        source: .authoredMesh(asset.id)
    )
    object.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = object

    let project = try DesignDocumentProjectBridge().sourceModel(for: document)
    let definitionID = ObjectDefinitionID(rawValue: "object.\(bodyNodeID.description)")
    let definition = try #require(project.objectDefinitions[definitionID])
    let evaluator = try DefaultDesignDocumentProjectEvaluatorFactory()
        .makeEvaluator(for: document, reusing: nil)
    let modelingSnapshot = try evaluator.evaluate(
        project: project,
        purpose: .modeling,
        revision: DocumentTransactionRevision(1)
    )
    let presentationSnapshot = try evaluator.evaluate(
        project: project,
        purpose: .presentation,
        revision: DocumentTransactionRevision(1)
    )
    let modeled = try #require(modelingSnapshot.occurrences.values.first {
        $0.definitionID == definitionID
    })
    let presented = try #require(presentationSnapshot.occurrences.values.first {
        $0.definitionID == definitionID
    })

    #expect(project.authoredMeshAssets[asset.id]?.provenance == .created)
    #expect(definition.representations.representations.count == 2)
    #expect(definition.representations.selection?.modeling == cadRepresentationID)
    #expect(definition.representations.selection?.presentation == meshRepresentationID)
    #expect(modeled.representationID == cadRepresentationID)
    #expect(modeled.reference == object.geometryRepresentations.source(for: .modeling))
    #expect(modeled.mesh != mesh)
    #expect(modeled.mesh.faceIDs.count > 0)
    #expect(modelingSnapshot.copyTelemetry.didCopy)
    #expect(presented.representationID == meshRepresentationID)
    #expect(presented.reference == GeometrySourceReference.authoredMesh(asset.id))
    #expect(presented.mesh == mesh)
    #expect(presentationSnapshot.copyTelemetry.didCopy == false)
}

@Test(.timeLimit(.minutes(1)))
func designDocumentEvaluatorFactoryStatesTheProductResourcePolicy() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bridge = DesignDocumentProjectBridge()
    let project = try bridge.sourceModel(for: session.document)

    // The product composition is the only seam that narrows an evaluation, so a
    // policy stated here must reach the engine that charges it. One vertex is
    // below anything the extruded rectangle can produce, so admitting it would
    // mean the stated policy never arrived.
    let narrowed = try EvaluationResourcePolicy(
        everyPurpose: EvaluationResourceLimits.standard.lowered(
            to: EvaluationResourceLimits(
                maximumSourceCount: 1,
                maximumVertexCount: 1,
                maximumFaceCount: 1,
                maximumCornerCount: 1,
                maximumTriangleCount: 1,
                maximumByteCount: 1
            )
        )
    )
    let refusingEvaluator = try DefaultDesignDocumentProjectEvaluatorFactory(
        resourcePolicy: narrowed
    ).makeEvaluator(for: session.document, reusing: session.currentEvaluation)

    var refusal: EvaluationError?
    do {
        _ = try refusingEvaluator.evaluate(
            project: project,
            purpose: .presentation,
            revision: session.transactionRevision
        )
    } catch let error as EvaluationError {
        refusal = error
    }
    #expect(refusal?.code == .resourceExhausted)

    // The same project under the product's stated default is admitted, so the
    // refusal above is the policy and not the fixture.
    let admittingEvaluator = try DefaultDesignDocumentProjectEvaluatorFactory()
        .makeEvaluator(for: session.document, reusing: session.currentEvaluation)
    let snapshot = try admittingEvaluator.evaluate(
        project: project,
        purpose: .presentation,
        revision: session.transactionRevision
    )
    #expect(!snapshot.occurrences.isEmpty)
}

private func bridgeTriangleMesh() throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: "mesh.bridge-presentation")
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}
