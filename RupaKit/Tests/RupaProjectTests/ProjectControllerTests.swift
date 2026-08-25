import Foundation
import Synchronization
import SwiftCAD
import Testing
import RupaCore
import RupaCoreTypes
import RupaEvaluation
@testable import RupaGeometry
import RupaProjectModel
@testable import RupaProjectPackage
@testable import RupaProject

@Test(.timeLimit(.minutes(1)))
func projectControllerPublishesCADPackageAndEvaluationAfterValidation() async throws {
    let controller = try makeController(document: .empty(named: "Before"))
    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.rename",
            commands: [.renameDocument(name: "After")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    #expect(result.baseTransactionRevision == DocumentTransactionRevision(0))
    #expect(result.transactionRevision == DocumentTransactionRevision(1))
    #expect(result.documentGeneration == DocumentGeneration(1))
    #expect(result.document.cadDocument.metadata.name == "After")
    #expect(try decodedProductName(result.package.productSource) == "After")
    #expect(result.evaluation.projectID == result.package.documentID)
    #expect(result.commandResults.count == 1)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "After")
    #expect(await controller.currentEvaluationSource().name == "After")
    #expect(await controller.currentPackage().cadSource == result.package.cadSource)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerPublishesOneCoherentStateSnapshot() async throws {
    let controller = try makeController(document: .empty(named: "Before"))

    _ = try await controller.evaluateCurrent()
    let initial = try await controller.currentState()

    #expect(initial.document.cadDocument.metadata.name == "Before")
    #expect(initial.evaluationSource.name == "Before")
    #expect(initial.evaluation.projectID == initial.evaluationSource.id)
    #expect(initial.evaluation.id.sourceRevision == initial.transactionRevision)
    #expect(initial.documentGeneration == DocumentGeneration(0))
    #expect(initial.transactionRevision == DocumentTransactionRevision(0))
    #expect(initial.publicationSequence == 1)
    #expect(initial.isDirty == false)
    #expect(initial.selection == .empty)
    #expect(initial.workspaceState.revision == WorkspaceRevision(0))
    #expect(initial.cadInteraction == nil)

    _ = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.coherent-state",
            commands: [.renameDocument(name: "After")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    let committed = try await controller.currentState()

    #expect(committed.document.cadDocument.metadata.name == "After")
    #expect(committed.evaluationSource.name == "After")
    #expect(try decodedProductName(committed.package.productSource) == "After")
    #expect(committed.evaluation.projectID == committed.evaluationSource.id)
    #expect(committed.evaluation.id.sourceRevision == committed.transactionRevision)
    #expect(committed.documentGeneration == DocumentGeneration(1))
    #expect(committed.transactionRevision == DocumentTransactionRevision(1))
    #expect(committed.publicationSequence == 2)
    #expect(committed.isDirty)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadsEvaluatesAndResavesMeshOnlyPackageWithoutCADAuthority() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("mesh-only.rupa")
        let resavedURL = directory.appendingPathComponent("mesh-only-resaved.rupa")
        let sourceDocument = try meshOnlyDocument(named: "Mesh Only")
        let controller = try makeController(document: sourceDocument)

        let initialEvaluation = try await controller.evaluateCurrent()
        let initialPackage = await controller.currentPackage()
        #expect(initialPackage.cadSource == nil)
        #expect(initialEvaluation.occurrences.values.contains {
            $0.reference == .authoredMesh("mesh.controller-only")
                && $0.mesh == sourceDocument.authoredMeshAssets["mesh.controller-only"]?.source
        })
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )

        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.rename-mesh-only",
                commands: [.renameDocument(name: "Changed")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(1)
        )

        #expect(loaded.document.cadDocument.metadata.name == "Mesh Only")
        #expect(loaded.document.id == sourceDocument.id)
        #expect(loaded.document.cadDocument.units == sourceDocument.cadDocument.units)
        #expect(loaded.document.hasAuthoritativeCADSource == false)
        #expect(loaded.package.cadSource == nil)
        #expect(loaded.document.authoredMeshAssets == sourceDocument.authoredMeshAssets)
        #expect(loaded.evaluation.occurrences.values.contains {
            $0.reference == .authoredMesh("mesh.controller-only")
        })
        #expect(loaded.documentGeneration == DocumentGeneration(0))
        #expect(loaded.transactionRevision == DocumentTransactionRevision(2))
        #expect(loaded.publicationSequence == 3)
        #expect(loaded.evaluation.id.sourceRevision == loaded.transactionRevision)
        #expect(loaded.evaluationSource.name == "Mesh Only")
        #expect(loaded.isDirty == false)
        #expect(loaded.selection == .empty)
        #expect(loaded.workspaceState.revision == WorkspaceRevision(0))
        #expect(loaded.cadInteraction == nil)
        let resaved = try await controller.save(
            to: resavedURL,
            expectedTransactionRevision: DocumentTransactionRevision(2)
        )
        #expect(resaved.document.cadSource == nil)
        #expect(resaved.document.authoredMeshAssets == sourceDocument.authoredMeshAssets)
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerCADTransactionPreservesAuthoredMeshAuthorityAndPresentationSelection() async throws {
    let sourceDocument = try cadAndMeshDocument(named: "Hybrid")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets["mesh.controller-presentation"])
    let sourceNode = try #require(sourceDocument.productMetadata.sceneNodes.first {
        $0.value.object?.geometryRepresentations.source(for: .presentation)
            == .authoredMesh(sourceAsset.id)
    })
    let sourceSelection = try #require(
        sourceNode.value.object?.geometryRepresentations.selection
    )
    let controller = try makeController(document: sourceDocument)
    let beforePackage = await controller.currentPackage()

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.rename-hybrid",
            commands: [.renameDocument(name: "Hybrid Renamed")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    let resultAsset = try #require(
        result.package.authoredMeshAssets[sourceAsset.id]
    )
    let resultSelection = try #require(
        result.document.productMetadata.sceneNodes[sourceNode.key]?
            .object?.geometryRepresentations.selection
    )
    #expect(beforePackage.cadSource != nil)
    #expect(result.package.cadSource != nil)
    #expect(result.package.cadSource != beforePackage.cadSource)
    #expect(resultAsset.id == sourceAsset.id)
    #expect(resultAsset.source == sourceAsset.source)
    #expect(resultAsset.provenance == sourceAsset.provenance)
    #expect(resultSelection == sourceSelection)
    let usesPresentationMesh = result.evaluation.occurrences.values.contains {
        $0.representationID == sourceSelection.presentation
            && $0.reference == .authoredMesh(sourceAsset.id)
    }
    #expect(usesPresentationMesh)
    #expect(result.evaluation.copyTelemetry.didCopy == false)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerPublishesMeshOnlyEditPackageAndEvaluationAtomically() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Mesh Edit")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let command = try authoredMeshVertexEditCommand(
        document: sourceDocument,
        sourceID: sourceAsset.id,
        position: GeometryPoint3D(x: 0, y: 0, z: 4)
    )
    let controller = try makeController(document: sourceDocument)

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.mesh-edit",
            geometrySourceCommands: [command],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    let editedAsset = try #require(result.document.authoredMeshAssets[sourceAsset.id])
    let evaluatedMesh = try #require(result.evaluation.occurrences.values.first?.mesh)
    #expect(result.commandResults.isEmpty)
    #expect(result.geometrySourceCommandResults.count == 1)
    #expect(result.geometrySourceCommandResults[0].didMutate)
    #expect(result.transactionRevision == DocumentTransactionRevision(1))
    #expect(editedAsset.contentIdentity != sourceAsset.contentIdentity)
    #expect(editedAsset.provenance == sourceAsset.provenance)
    #expect(result.package.authoredMeshAssets[sourceAsset.id] == editedAsset)
    #expect(try editedAsset.source.position(of: editedAsset.source.vertexIDs[0]).z == 4)
    #expect(evaluatedMesh == editedAsset.source)
    #expect(
        evaluatedMesh.vertexPositions.storage.chunkIdentities
            == editedAsset.source.vertexPositions.storage.chunkIdentities
    )
    #expect(!result.evaluation.copyTelemetry.didCopy)
    #expect(
        await controller.currentDocument().authoredMeshAssets[sourceAsset.id]
            == editedAsset
    )
}

@Test(.timeLimit(.minutes(1)))
func projectControllerMeshNoOpPreservesRevisionPackageAndBufferIdentity() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Mesh No-op")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let originalPosition = try sourceAsset.source.position(
        of: try #require(sourceAsset.source.vertexIDs.first)
    )
    let controller = try makeController(document: sourceDocument)
    let retainedPackage = await controller.currentPackage()

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.mesh-no-op",
            geometrySourceCommands: [
                try authoredMeshVertexEditCommand(
                    document: sourceDocument,
                    sourceID: sourceAsset.id,
                    position: originalPosition
                ),
            ],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    let retainedAsset = try #require(result.document.authoredMeshAssets[sourceAsset.id])
    #expect(!result.geometrySourceCommandResults[0].didMutate)
    #expect(result.documentGeneration == DocumentGeneration(0))
    #expect(result.transactionRevision == DocumentTransactionRevision(0))
    #expect(result.package.authoredMeshAssets == retainedPackage.authoredMeshAssets)
    #expect(result.package.retainsUnreferencedSourceBlobs)
    #expect(
        retainedAsset.source.vertexPositions.storage.chunkIdentities
            == sourceAsset.source.vertexPositions.storage.chunkIdentities
    )
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerAppliesCADCommandsBeforeGeometrySourceCommands() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Before")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let controller = try makeController(
        document: sourceDocument,
        geometrySourceCommandApplier: NameRequiringGeometrySourceCommandApplier(
            requiredName: "After"
        )
    )

    let result = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.ordered-mixed-commands",
            commands: [.renameDocument(name: "After")],
            geometrySourceCommands: [
                try authoredMeshVertexEditCommand(
                    document: sourceDocument,
                    sourceID: sourceAsset.id,
                    position: GeometryPoint3D(x: 0, y: 0, z: 5)
                ),
            ],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )

    #expect(result.document.cadDocument.metadata.name == "After")
    #expect(result.commandResults.count == 1)
    #expect(result.geometrySourceCommandResults.count == 1)
    #expect(result.documentGeneration == DocumentGeneration(2))
    #expect(result.transactionRevision == DocumentTransactionRevision(1))
    #expect(
        try result.document.authoredMeshAssets[sourceAsset.id]?
            .source.position(of: sourceAsset.source.vertexIDs[0]).z == 5
    )
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsStaleMeshIdentityWithoutPublishing() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Stale Mesh")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let staleCommand = try authoredMeshVertexEditCommand(
        document: sourceDocument,
        sourceID: sourceAsset.id,
        position: GeometryPoint3D(x: 0, y: 0, z: 7)
    )
    let controller = try makeController(document: sourceDocument)
    _ = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.first-mesh-edit",
            geometrySourceCommands: [staleCommand],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    let retainedDocument = await controller.currentDocument()
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.stale-mesh-identity",
                geometrySourceCommands: [staleCommand],
                expectedTransactionRevision: DocumentTransactionRevision(1)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .transactionInvalid)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    #expect(await controller.currentDocument().authoredMeshAssets == retainedDocument.authoredMeshAssets)
    #expect(await controller.currentPackage().authoredMeshAssets == retainedPackage.authoredMeshAssets)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerMeshEvaluationFailureDoesNotPublishOrEnableBlobCollection() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Rejected Mesh")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let controller = try makeController(
        document: sourceDocument,
        evaluator: FailingProjectEvaluator()
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.mesh-evaluation-failure",
                geometrySourceCommands: [
                    try authoredMeshVertexEditCommand(
                        document: sourceDocument,
                        sourceID: sourceAsset.id,
                        position: GeometryPoint3D(x: 0, y: 0, z: 8)
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(await controller.currentDocument().authoredMeshAssets == sourceDocument.authoredMeshAssets)
    #expect(await controller.currentPackage().authoredMeshAssets == retainedPackage.authoredMeshAssets)
    #expect(await controller.currentPackage().retainsUnreferencedSourceBlobs)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerMeshProductEncodingFailureDoesNotPublish() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Codec Mesh")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let controller = try makeController(
        document: sourceDocument,
        productSourceCodec: MeshPositionRejectingProductSourceCodec(rejectedZ: 9)
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.mesh-product-codec-failure",
                geometrySourceCommands: [
                    try authoredMeshVertexEditCommand(
                        document: sourceDocument,
                        sourceID: sourceAsset.id,
                        position: GeometryPoint3D(x: 0, y: 0, z: 9)
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .productSourceFailed)
    #expect(await controller.currentDocument().authoredMeshAssets == sourceDocument.authoredMeshAssets)
    #expect(await controller.currentPackage().authoredMeshAssets == retainedPackage.authoredMeshAssets)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerMeshPackageValidationFailureDoesNotPublish() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Validation Mesh")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let controller = try makeController(
        document: sourceDocument,
        packageValidator: MeshPositionRejectingPackageValidator(rejectedZ: 10)
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.mesh-package-validation-failure",
                geometrySourceCommands: [
                    try authoredMeshVertexEditCommand(
                        document: sourceDocument,
                        sourceID: sourceAsset.id,
                        position: GeometryPoint3D(x: 0, y: 0, z: 10)
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .packageFailed)
    #expect(await controller.currentDocument().authoredMeshAssets == sourceDocument.authoredMeshAssets)
    #expect(await controller.currentPackage().authoredMeshAssets == retainedPackage.authoredMeshAssets)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLossyProductCodecBeforePublishing() async throws {
    let controller = try makeController(
        document: try meshOnlyDocument(named: "Before"),
        productSourceCodec: NameCorruptingProductSourceCodec(triggerName: "After")
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-product",
                commands: [.renameDocument(name: "After")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLossyCADCodecBeforePublishing() async throws {
    let sourceDocument = try cadAndMeshDocument(named: "Before")
    let controller = try makeController(
        document: sourceDocument,
        cadSourceCodec: NameCorruptingCADSourceCodec(triggerName: "After")
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-cad",
                commands: [.renameDocument(name: "After")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentPackage().cadSource == retainedPackage.cadSource)
    #expect(
        await controller.currentPackage().authoredMeshAssets
            == retainedPackage.authoredMeshAssets
    )
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLostProductModelingSettingsBeforePublishing() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Before")
    let controller = try makeController(
        document: sourceDocument,
        productSourceCodec: ModelingSettingsCorruptingProductSourceCodec(
            triggerName: "After"
        )
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-product-settings",
                commands: [.renameDocument(name: "After")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().modelingSettings == sourceDocument.modelingSettings)
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLostCADParametersBeforePublishing() async throws {
    let sourceDocument = DesignDocument.empty(named: "Parameters")
    let controller = try makeController(
        document: sourceDocument,
        cadSourceCodec: ParameterDroppingCADSourceCodec()
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.lossy-cad-parameters",
                commands: [
                    .upsertParameter(
                        name: "width",
                        expression: .constant(.length(1.0, unit: .meter)),
                        kind: .length
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .sourceMismatch)
    #expect(await controller.currentDocument().cadDocument.parameters.parameters.isEmpty)
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentPackage().cadSource == nil)
    #expect(await controller.currentEvaluationSource().name == "Parameters")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsUnsavableStagedPackageBeforePublishing() async throws {
    let sourceDocument = try meshOnlyDocument(named: "Before")
    let initialProductByteCount = try JSONProjectProductSourceCodec()
        .encode(sourceDocument).data.count
    var limits = ProjectPackageResourceLimits.standard
    limits.maximumProductSourceByteCount = initialProductByteCount
    let validator = ProjectPackageStore(limits: limits)
    let controller = try makeController(
        document: sourceDocument,
        packageValidator: validator
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.unsavable-package",
                commands: [.renameDocument(name: "A much longer staged Product name")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .packageFailed)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsProductCADMismatchWithoutPublishing() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("mismatch.rupa")
        let sourceController = try makeController(
            document: try cadAndMeshDocument(named: "Matched")
        )
        let sourcePackage = await sourceController.currentPackage()
        let sourceCAD = try #require(sourcePackage.cadSource)
        var mismatchedCAD = try JSONProjectCADSourceCodec().decode(sourceCAD)
        mismatchedCAD.metadata.name = "Mismatched"
        let mismatchedPackage = try sourcePackage.replacingSources(
            documentID: sourcePackage.documentID,
            product: sourcePackage.productSource,
            cad: JSONProjectCADSourceCodec().encode(mismatchedCAD),
            authoredMeshAssets: sourcePackage.authoredMeshAssets
        )
        _ = try ProjectPackageStore().save(mismatchedPackage, to: url)

        let retainedDocument = try meshOnlyDocument(named: "Retained")
        let controller = try makeController(document: retainedDocument)
        let retainedPackage = await controller.currentPackage()
        var caught: ProjectControllerError?
        do {
            _ = try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .sourceMismatch)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerProductDecodeFailureDoesNotPublishLoadedPackage() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("invalid-product.rupa")
        let sourceController = try makeController(
            document: try meshOnlyDocument(named: "Invalid")
        )
        let sourcePackage = await sourceController.currentPackage()
        let invalidProduct = try ProjectPackageProductSource(
            data: Data("{\"schemaVersion\":99}".utf8)
        )
        let invalidPackage = try sourcePackage.replacingSources(
            documentID: sourcePackage.documentID,
            product: invalidProduct,
            cad: sourcePackage.cadSource,
            authoredMeshAssets: sourcePackage.authoredMeshAssets
        )
        _ = try ProjectPackageStore().save(invalidPackage, to: url)

        let controller = try makeController(
            document: try meshOnlyDocument(named: "Retained")
        )
        let retainedPackage = await controller.currentPackage()
        var caught: ProjectControllerError?
        do {
            _ = try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .productSourceFailed)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadEvaluationFailureDoesNotPublishStagedSources() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("evaluation-failure.rupa")
        let sourceController = try makeController(
            document: try meshOnlyDocument(named: "Rejected")
        )
        _ = try await sourceController.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let controller = try makeController(
            document: try meshOnlyDocument(named: "Retained"),
            evaluator: NameRejectingProjectEvaluator(rejectedName: "Rejected")
        )
        let retainedPackage = await controller.currentPackage()
        var caught: ProjectControllerError?

        do {
            _ = try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .evaluationFailed)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerCancelledLoadDoesNotPublishStagedSources() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("cancelled-load.rupa")
        let sourceController = try makeController(
            document: try meshOnlyDocument(named: "Blocked")
        )
        _ = try await sourceController.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let gate = BlockingEvaluationGate(blockedSourceName: "Blocked")
        defer { gate.releaseFirstEvaluation() }
        let controller = try makeController(
            document: try meshOnlyDocument(named: "Retained"),
            evaluator: BlockingProjectEvaluator(gate: gate)
        )
        let retainedPackage = await controller.currentPackage()
        let load = Task {
            try await controller.load(
                from: url,
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        }
        while !gate.didStartFirstEvaluation {
            try await Task.sleep(for: .milliseconds(1))
        }
        load.cancel()
        gate.releaseFirstEvaluation()

        var wasCancelled = false
        do {
            _ = try await load.value
        } catch is CancellationError {
            wasCancelled = true
        }
        #expect(wasCancelled)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Retained")
        #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
        #expect(await controller.currentEvaluationSource().name == "Retained")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerDoesNotPublishWhenEvaluationFails() async throws {
    let initial = DesignDocument.empty(named: "Before")
    let controller = try makeController(
        document: initial,
        evaluator: FailingProjectEvaluator()
    )
    let initialPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.failure",
                commands: [.renameDocument(name: "Never Published")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentPackage().cadSource == initialPackage.cadSource)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerDoesNotPublishWhenEvaluatorPreparationFails() async throws {
    let controller = try makeController(
        document: try meshOnlyDocument(named: "Before"),
        evaluatorPreparer: NameRejectingProjectEvaluatorPreparer(
            rejectedName: "After"
        )
    )
    let retainedPackage = await controller.currentPackage()
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.preparation-failure",
                commands: [.renameDocument(name: "After")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Before")
    #expect(await controller.currentPackage().productSource == retainedPackage.productSource)
    #expect(await controller.currentEvaluationSource().name == "Before")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsStaleRequestBeforeStaging() async throws {
    let controller = try makeController(document: .empty(named: "Before"))
    _ = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.first",
            commands: [.renameDocument(name: "Committed")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    var caught: ProjectControllerError?

    do {
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.stale",
                commands: [.renameDocument(name: "Rejected")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    } catch let error as ProjectControllerError {
        caught = error
    }

    #expect(caught?.code == .revisionConflict)
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Committed")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    #expect(try await controller.currentState().publicationSequence == 1)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsPublicationWhenConcurrentCallerWins() async throws {
    let gate = BlockingEvaluationGate()
    let controller = try makeController(
        document: .empty(named: "Before"),
        evaluator: BlockingProjectEvaluator(gate: gate)
    )
    let first = Task {
        try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.first",
                commands: [.renameDocument(name: "First")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    }
    while !gate.didStartFirstEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }

    let second = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.second",
            commands: [.renameDocument(name: "Second")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    gate.releaseFirstEvaluation()

    var firstError: ProjectControllerError?
    do {
        _ = try await first.value
    } catch let error as ProjectControllerError {
        firstError = error
    }
    #expect(firstError?.code == .revisionConflict)
    #expect(second.transactionRevision == DocumentTransactionRevision(1))
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Second")
    #expect(await controller.currentEvaluationSource().name == "Second")
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    #expect(try await controller.currentState().publicationSequence == 1)
}

@Test(.timeLimit(.minutes(1)))
func projectControllerCancelledMeshCommitDoesNotPublishStagedAuthority() async throws {
    let sourceDocument = try meshOnlyDocument(named: "First")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let gate = BlockingEvaluationGate()
    defer { gate.releaseFirstEvaluation() }
    let controller = try makeController(
        document: sourceDocument,
        evaluator: BlockingProjectEvaluator(gate: gate)
    )
    let retainedPackage = await controller.currentPackage()
    let commit = Task {
        try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.cancelled-mesh",
                geometrySourceCommands: [
                    try authoredMeshVertexEditCommand(
                        document: sourceDocument,
                        sourceID: sourceAsset.id,
                        position: GeometryPoint3D(x: 0, y: 0, z: 11)
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    }
    while !gate.didStartFirstEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }
    commit.cancel()
    gate.releaseFirstEvaluation()

    var wasCancelled = false
    do {
        _ = try await commit.value
    } catch is CancellationError {
        wasCancelled = true
    }

    #expect(wasCancelled)
    #expect(await controller.currentDocument().authoredMeshAssets == sourceDocument.authoredMeshAssets)
    #expect(await controller.currentPackage().authoredMeshAssets == retainedPackage.authoredMeshAssets)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLateMeshPublicationLosesToNewerCommit() async throws {
    let sourceDocument = try meshOnlyDocument(named: "First")
    let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
    let gate = BlockingEvaluationGate()
    defer { gate.releaseFirstEvaluation() }
    let controller = try makeController(
        document: sourceDocument,
        evaluator: BlockingProjectEvaluator(gate: gate)
    )
    let first = Task {
        try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.late-mesh",
                geometrySourceCommands: [
                    try authoredMeshVertexEditCommand(
                        document: sourceDocument,
                        sourceID: sourceAsset.id,
                        position: GeometryPoint3D(x: 0, y: 0, z: 12)
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
    }
    while !gate.didStartFirstEvaluation {
        try await Task.sleep(for: .milliseconds(1))
    }

    let second = try await controller.commit(
        ProjectSourceTransaction(
            name: "fixture.winning-cad",
            commands: [.renameDocument(name: "Second")],
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
    )
    gate.releaseFirstEvaluation()

    var firstError: ProjectControllerError?
    do {
        _ = try await first.value
    } catch let error as ProjectControllerError {
        firstError = error
    }

    #expect(firstError?.code == .revisionConflict)
    #expect(second.transactionRevision == DocumentTransactionRevision(1))
    #expect(await controller.currentDocument().cadDocument.metadata.name == "Second")
    #expect(await controller.currentDocument().authoredMeshAssets == sourceDocument.authoredMeshAssets)
    #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
}

@Test(.timeLimit(.minutes(1)))
func projectControllerMeshCommitReusesUnchangedBlobAndCollectsSupersededBlob() async throws {
    try await withTemporaryDirectory { directory in
        let initialURL = directory.appendingPathComponent("initial.rupa")
        let editedURL = directory.appendingPathComponent("edited.rupa")
        let sourceDocument = try twoMeshDocument(named: "Two Meshes")
        let editedSourceID: GeometrySourceID = "mesh.controller-only"
        let editedAsset = try #require(sourceDocument.authoredMeshAssets[editedSourceID])
        let controller = try makeController(document: sourceDocument)
        let initialSave = try await controller.save(
            to: initialURL,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let initialBlobPaths = sourceBlobPaths(in: initialSave.document)

        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.collect-superseded-mesh",
                geometrySourceCommands: [
                    try authoredMeshVertexEditCommand(
                        document: sourceDocument,
                        sourceID: editedSourceID,
                        position: GeometryPoint3D(x: 0, y: 0, z: 13)
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
        #expect(await controller.currentPackage().retainsUnreferencedSourceBlobs == false)
        let editedSave = try await controller.save(
            to: editedURL,
            expectedTransactionRevision: DocumentTransactionRevision(1)
        )
        let editedBlobPaths = sourceBlobPaths(in: editedSave.document)

        #expect(initialBlobPaths.count == 2)
        #expect(editedBlobPaths.count == 2)
        #expect(initialBlobPaths.intersection(editedBlobPaths).count == 1)
        #expect(editedSave.report.encodedSourceBlobCount == 1)
        #expect(editedSave.report.reusedSourceBlobCount == 1)
        #expect(
            editedSave.document.authoredMeshAssets[editedSourceID]?.contentIdentity
                != editedAsset.contentIdentity
        )
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRoutesSaveAndLoadThroughCoherentPackageState() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let controller = try makeController(document: .empty(named: "Saved"))
        let saved = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        #expect(try decodedProductName(saved.document.productSource) == "Saved")

        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.change",
                commands: [.renameDocument(name: "Changed")],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(1)
        )

        #expect(loaded.document.cadDocument.metadata.name == "Saved")
        #expect(try decodedProductName(loaded.package.productSource) == "Saved")
        #expect(loaded.transactionRevision == DocumentTransactionRevision(2))
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Saved")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(2))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerLoadInvalidatesPreLoadTransactionRevisions() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let controller = try makeController(document: .empty(named: "Loaded"))
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )

        #expect(loaded.transactionRevision == DocumentTransactionRevision(1))
        var caught: ProjectControllerError?
        do {
            _ = try await controller.commit(
                ProjectSourceTransaction(
                    name: "fixture.stale-after-load",
                    commands: [.renameDocument(name: "Rejected")],
                    expectedTransactionRevision: DocumentTransactionRevision(0)
                )
            )
        } catch let error as ProjectControllerError {
            caught = error
        }
        #expect(caught?.code == .revisionConflict)
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Loaded")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerRejectsLateCommitAfterPackageLoadPublishes() async throws {
    try await withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("project.swcad")
        let gate = BlockingEvaluationGate()
        defer { gate.releaseFirstEvaluation() }
        let controller = try makeController(
            document: .empty(named: "Loaded"),
            evaluator: BlockingProjectEvaluator(gate: gate)
        )
        _ = try await controller.save(
            to: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        let commit = Task {
            try await controller.commit(
                ProjectSourceTransaction(
                    name: "fixture.late",
                    commands: [.renameDocument(name: "First")],
                    expectedTransactionRevision: DocumentTransactionRevision(0)
                )
            )
        }
        while !gate.didStartFirstEvaluation {
            try await Task.sleep(for: .milliseconds(1))
        }

        let loaded = try await controller.load(
            from: url,
            expectedTransactionRevision: DocumentTransactionRevision(0)
        )
        gate.releaseFirstEvaluation()

        var commitError: ProjectControllerError?
        do {
            _ = try await commit.value
        } catch let error as ProjectControllerError {
            commitError = error
        }
        #expect(commitError?.code == .revisionConflict)
        #expect(loaded.transactionRevision == DocumentTransactionRevision(1))
        #expect(await controller.currentDocument().cadDocument.metadata.name == "Loaded")
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerFailedSaveRetainsCurrentAggregate() async throws {
    try await withTemporaryDirectory { directory in
        let controller = try makeController(
            document: .empty(named: "Retained"),
            packageWriter: FailingPackageWriter()
        )
        let before = await controller.currentPackage()
        var caught: ProjectControllerError?

        do {
            _ = try await controller.save(
                to: directory.appendingPathComponent("failed.swcad"),
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .packageFailed)
        #expect(await controller.currentPackage().productSource == before.productSource)
        #expect(await controller.currentPackage().cadSource == before.cadSource)
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(0))
    }
}

@Test(.timeLimit(.minutes(1)))
func projectControllerFailedSaveRetainsPublishedMeshAuthority() async throws {
    try await withTemporaryDirectory { directory in
        let sourceDocument = try meshOnlyDocument(named: "Retained Mesh")
        let sourceAsset = try #require(sourceDocument.authoredMeshAssets.values.first)
        let controller = try makeController(
            document: sourceDocument,
            packageWriter: FailingPackageWriter()
        )
        _ = try await controller.commit(
            ProjectSourceTransaction(
                name: "fixture.mesh-before-failed-save",
                geometrySourceCommands: [
                    try authoredMeshVertexEditCommand(
                        document: sourceDocument,
                        sourceID: sourceAsset.id,
                        position: GeometryPoint3D(x: 0, y: 0, z: 14)
                    ),
                ],
                expectedTransactionRevision: DocumentTransactionRevision(0)
            )
        )
        let retainedDocument = await controller.currentDocument()
        let retainedPackage = await controller.currentPackage()
        var caught: ProjectControllerError?

        do {
            _ = try await controller.save(
                to: directory.appendingPathComponent("failed-mesh.rupa"),
                expectedTransactionRevision: DocumentTransactionRevision(1)
            )
        } catch let error as ProjectControllerError {
            caught = error
        }

        #expect(caught?.code == .packageFailed)
        #expect(await controller.currentDocument().authoredMeshAssets == retainedDocument.authoredMeshAssets)
        #expect(await controller.currentPackage().authoredMeshAssets == retainedPackage.authoredMeshAssets)
        #expect(await controller.currentTransactionRevision() == DocumentTransactionRevision(1))
    }
}

private func makeController(
    document: DesignDocument,
    evaluator: any ProjectEvaluating = ProjectEvaluationEngine(),
    evaluatorPreparer: (any ProjectEvaluatorPreparing)? = nil,
    productSourceCodec: any ProjectProductSourceCoding = JSONProjectProductSourceCodec(),
    cadSourceCodec: any ProjectCADSourceCoding = JSONProjectCADSourceCodec(),
    packageWriter: any ProjectPackageWriting = ProjectPackageStore(),
    packageValidator: any ProjectPackageValidating = ProjectPackageStore(),
    geometrySourceCommandApplier: any GeometrySourceCommandApplying =
        DefaultGeometrySourceCommandApplier()
) throws -> ProjectController {
    try ProjectController(
        document: document,
        evaluatorPreparer: evaluatorPreparer
            ?? StaticProjectEvaluatorPreparer(evaluator: evaluator),
        projector: FixtureProjector(),
        productSourceCodec: productSourceCodec,
        cadSourceCodec: cadSourceCodec,
        packageWriter: packageWriter,
        packageValidator: packageValidator,
        geometrySourceCommandApplier: geometrySourceCommandApplier
    )
}

private struct StaticProjectEvaluatorPreparer: ProjectEvaluatorPreparing {
    let evaluator: any ProjectEvaluating

    func makeEvaluator(
        for _: DesignDocument,
        reusing _: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        evaluator
    }
}

private struct NameRejectingProjectEvaluatorPreparer: ProjectEvaluatorPreparing {
    let rejectedName: String

    func makeEvaluator(
        for document: DesignDocument,
        reusing _: DocumentEvaluationContext?
    ) throws -> any ProjectEvaluating {
        guard document.cadDocument.metadata.name != rejectedName else {
            throw EvaluatorPreparationFixtureError()
        }
        return ProjectEvaluationEngine()
    }
}

private struct EvaluatorPreparationFixtureError: Error {}

private struct GeometryCommandOrderFixtureError: Error {}

private struct NameRequiringGeometrySourceCommandApplier: GeometrySourceCommandApplying {
    let requiredName: String

    func apply(
        _ command: GeometrySourceCommand,
        to document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> GeometrySourceCommandApplication {
        guard document.cadDocument.metadata.name == requiredName else {
            throw GeometryCommandOrderFixtureError()
        }
        return try DefaultGeometrySourceCommandApplier().apply(
            command,
            to: document,
            objectRegistry: objectRegistry
        )
    }
}

private struct FixtureProjector: ProjectSourceProjecting {
    func project(_ document: DesignDocument) throws -> ProjectSourceModel {
        var parentByChild: [SceneNodeID: SceneNodeID] = [:]
        for parent in document.productMetadata.sceneNodes.values {
            for childID in parent.childIDs {
                parentByChild[childID] = parent.id
            }
        }
        var definitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
        for node in document.productMetadata.sceneNodes.values {
            let definitionID = ObjectDefinitionID(rawValue: "object.\(node.id.description)")
            let occurrenceID = SceneOccurrenceID(rawValue: "scene.\(node.id.description)")
            definitions[definitionID] = ObjectDefinition(
                id: definitionID,
                name: node.name,
                representations: node.object?.category == .body
                    ? node.object?.geometryRepresentations ?? .empty
                    : .empty
            )
            occurrences[occurrenceID] = SceneOccurrence(
                id: occurrenceID,
                definitionID: definitionID,
                parentID: parentByChild[node.id].map {
                    SceneOccurrenceID(rawValue: "scene.\($0.description)")
                },
                localTransform: .identity
            )
        }
        return try ProjectSourceModel(
            id: ProjectID(rawValue: "project.\(document.id.description)"),
            name: document.cadDocument.metadata.name ?? "Untitled",
            authoredMeshAssets: document.authoredMeshAssets,
            objectDefinitions: definitions,
            occurrences: occurrences,
            rootOccurrenceIDs: document.productMetadata.rootSceneNodeIDs.map {
                SceneOccurrenceID(rawValue: "scene.\($0.description)")
            }
        )
    }
}

private func decodedProductName(_ source: ProjectPackageProductSource) throws -> String? {
    try JSONProjectProductSourceCodec().decode(source).name
}

private struct NameCorruptingProductSourceCodec: ProjectProductSourceCoding {
    let triggerName: String

    func encode(_ document: DesignDocument) throws -> ProjectPackageProductSource {
        guard document.cadDocument.metadata.name == triggerName else {
            return try JSONProjectProductSourceCodec().encode(document)
        }
        var corrupted = document
        corrupted.cadDocument.metadata.name = "Corrupted"
        return try JSONProjectProductSourceCodec().encode(corrupted)
    }

    func decode(_ source: ProjectPackageProductSource) throws -> ProjectProductSourceModel {
        try JSONProjectProductSourceCodec().decode(source)
    }
}

private struct NameCorruptingCADSourceCodec: ProjectCADSourceCoding {
    let triggerName: String

    func encode(_ document: CADDocument) throws -> ProjectPackageCADSource {
        guard document.metadata.name == triggerName else {
            return try JSONProjectCADSourceCodec().encode(document)
        }
        var corrupted = document
        corrupted.metadata.name = "Corrupted"
        return try JSONProjectCADSourceCodec().encode(corrupted)
    }

    func decode(_ source: ProjectPackageCADSource) throws -> CADDocument {
        try JSONProjectCADSourceCodec().decode(source)
    }
}

private struct ModelingSettingsCorruptingProductSourceCodec: ProjectProductSourceCoding {
    let triggerName: String

    func encode(_ document: DesignDocument) throws -> ProjectPackageProductSource {
        try JSONProjectProductSourceCodec().encode(document)
    }

    func decode(_ source: ProjectPackageProductSource) throws -> ProjectProductSourceModel {
        let decoded = try JSONProjectProductSourceCodec().decode(source)
        guard decoded.name == triggerName else {
            return decoded
        }
        let current = decoded.modelingSettings.tessellationOptions
        return try ProjectProductSourceModel(
            documentID: decoded.documentID,
            name: decoded.name,
            units: decoded.units,
            modelingSettings: DocumentModelingSettings(
                tolerance: decoded.modelingSettings.tolerance,
                tessellationOptions: TessellationOptions(
                    linearTolerance: current.linearTolerance * 2.0,
                    angularTolerance: current.angularTolerance,
                    maxEdgeLength: current.maxEdgeLength
                )
            ),
            productMetadata: decoded.productMetadata
        )
    }
}

private struct ParameterDroppingCADSourceCodec: ProjectCADSourceCoding {
    func encode(_ document: CADDocument) throws -> ProjectPackageCADSource {
        var corrupted = document
        corrupted.parameters = ParameterTable(revision: document.parameters.revision)
        return try JSONProjectCADSourceCodec().encode(corrupted)
    }

    func decode(_ source: ProjectPackageCADSource) throws -> CADDocument {
        try JSONProjectCADSourceCodec().decode(source)
    }
}

private struct MeshPositionRejectingProductSourceCodec: ProjectProductSourceCoding {
    let rejectedZ: Double

    func encode(_ document: DesignDocument) throws -> ProjectPackageProductSource {
        if try documentContainsVertex(atZ: rejectedZ, document: document) {
            throw MeshSourceRejectionFixtureError()
        }
        return try JSONProjectProductSourceCodec().encode(document)
    }

    func decode(_ source: ProjectPackageProductSource) throws -> ProjectProductSourceModel {
        try JSONProjectProductSourceCodec().decode(source)
    }
}

private struct MeshPositionRejectingPackageValidator: ProjectPackageValidating {
    let rejectedZ: Double

    func validateForSave(_ document: ProjectPackageDocument) throws {
        try ProjectPackageStore().validateForSave(document)
        if try assetsContainVertex(atZ: rejectedZ, assets: document.authoredMeshAssets) {
            throw MeshSourceRejectionFixtureError()
        }
    }
}

private struct MeshSourceRejectionFixtureError: Error {}

private struct FailingProjectEvaluator: ProjectEvaluating {
    func evaluate(
        project _: ProjectSourceModel,
        purpose _: GeometryRepresentationPurpose,
        revision _: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        throw EvaluationError(
            code: .sourceUnavailable,
            message: "Fixture evaluation failed."
        )
    }
}

private struct NameRejectingProjectEvaluator: ProjectEvaluating {
    let rejectedName: String

    func evaluate(
        project: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        guard project.name != rejectedName else {
            throw EvaluationError(
                code: .sourceUnavailable,
                message: "Fixture rejected the staged source."
            )
        }
        return try ProjectEvaluationEngine().evaluate(
            project: project,
            purpose: purpose,
            revision: revision
        )
    }
}

private final class BlockingEvaluationGate: Sendable {
    private struct State {
        var didStartFirstEvaluation = false
        var canFinishFirstEvaluation = false
    }

    private let state = Mutex(State())
    private let blockedSourceName: String

    init(blockedSourceName: String = "First") {
        self.blockedSourceName = blockedSourceName
    }

    var didStartFirstEvaluation: Bool {
        state.withLock { $0.didStartFirstEvaluation }
    }

    func waitIfNeeded(for sourceName: String) {
        guard sourceName == blockedSourceName else {
            return
        }
        state.withLock { $0.didStartFirstEvaluation = true }
        while !state.withLock({ $0.canFinishFirstEvaluation }) {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    func releaseFirstEvaluation() {
        state.withLock { $0.canFinishFirstEvaluation = true }
    }
}

private struct BlockingProjectEvaluator: ProjectEvaluating {
    let gate: BlockingEvaluationGate

    func evaluate(
        project source: ProjectSourceModel,
        purpose: GeometryRepresentationPurpose,
        revision: DocumentTransactionRevision
    ) throws -> EvaluatedProjectSnapshot {
        gate.waitIfNeeded(for: source.name)
        return try ProjectEvaluationEngine().evaluate(
            project: source,
            purpose: purpose,
            revision: revision
        )
    }
}

private struct FailingPackageWriter: ProjectPackageWriting {
    func save(
        _: ProjectPackageDocument,
        to _: URL
    ) throws -> ProjectPackageSaveResult {
        throw ProjectPackageError(
            code: .atomicSaveFailure,
            message: "Fixture save failure."
        )
    }
}

private func meshOnlyDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let mesh = try triangleMesh(identity: "mesh.controller-only")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID = "representation.controller-only"
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: representationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    _ = try document.validate()
    return document
}

private func twoMeshDocument(named name: String) throws -> DesignDocument {
    var document = try meshOnlyDocument(named: name)
    let mesh = try triangleMesh(identity: "mesh.controller-secondary")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let representationID: GeometryRepresentationID =
        "representation.controller-secondary"
    document.authoredMeshAssets[asset.id] = asset
    _ = try document.productMetadata.appendSceneNodeToFirstRoot(
        name: "Secondary Mesh",
        reference: .authoredMesh(asset.id),
        object: ObjectDescriptor(
            category: .body,
            geometryRole: .mesh,
            geometryRepresentations: representationSet(
                representationID: representationID,
                source: .authoredMesh(asset.id)
            )
        )
    )
    _ = try document.validate()
    return document
}

private func cadAndMeshDocument(named name: String) throws -> DesignDocument {
    var document = DesignDocument.empty(named: name)
    let bodyFeatureID = try document.createExtrudedRectangle(
        name: "Body",
        plane: .xy,
        width: .length(1, .meter),
        height: .length(1, .meter),
        depth: .length(1, .meter),
        direction: .normal
    )
    let bodyNodeID = try #require(document.productMetadata.sceneNodes.first {
        $0.value.reference == .body(bodyFeatureID)
    }?.key)
    var object = try #require(document.productMetadata.sceneNodes[bodyNodeID]?.object)
    let cadRepresentationID = try #require(
        object.geometryRepresentations.selection?.modeling
    )
    let mesh = try triangleMesh(identity: "mesh.controller-presentation")
    let asset = try AuthoredMeshAsset(source: mesh, provenance: .created)
    let meshRepresentationID: GeometryRepresentationID =
        "representation.controller-presentation"
    document.authoredMeshAssets[asset.id] = asset
    object.geometryRepresentations.representations[meshRepresentationID] =
        GeometryRepresentation(
            id: meshRepresentationID,
            source: .authoredMesh(asset.id)
        )
    object.geometryRepresentations.selection = GeometryRepresentationSelection(
        modeling: cadRepresentationID,
        presentation: meshRepresentationID
    )
    document.productMetadata.sceneNodes[bodyNodeID]?.object = object
    _ = try document.validate()
    return document
}

private func representationSet(
    representationID: GeometryRepresentationID,
    source: GeometrySourceReference
) -> GeometryRepresentationSet {
    GeometryRepresentationSet(
        representations: [
            representationID: GeometryRepresentation(
                id: representationID,
                source: source
            ),
        ],
        selection: GeometryRepresentationSelection(
            modeling: representationID,
            presentation: representationID
        )
    )
}

private func triangleMesh(identity: GeometrySourceID) throws -> MeshSource {
    var builder = MeshSourceBuilder(identity: identity)
    let first = try builder.addVertex(GeometryPoint3D(x: 0, y: 0, z: 0))
    let second = try builder.addVertex(GeometryPoint3D(x: 1, y: 0, z: 0))
    let third = try builder.addVertex(GeometryPoint3D(x: 0, y: 1, z: 0))
    _ = try builder.addFace(vertexIDs: [first, second, third])
    return try builder.build()
}

private func authoredMeshVertexEditCommand(
    document: DesignDocument,
    sourceID: GeometrySourceID,
    position: GeometryPoint3D
) throws -> GeometrySourceCommand {
    let asset = try #require(document.authoredMeshAssets[sourceID])
    let match = try #require(document.productMetadata.sceneNodes.first { node in
        node.value.object?.geometryRepresentations.representations.values.contains {
            $0.source == .authoredMesh(sourceID)
        } == true
    })
    let representationID = try #require(
        match.value.object?.geometryRepresentations.representations.first {
            $0.value.source == .authoredMesh(sourceID)
        }?.key
    )
    let vertexID = try #require(asset.source.vertexIDs.first)
    return .editAuthoredMesh(
        .setVertexPosition(
            target: AuthoredMeshEditTarget(
                sceneNodeID: match.key,
                representationID: representationID,
                sourceID: sourceID,
                expectedSourceIdentity: asset.contentIdentity
            ),
            vertexID: vertexID,
            position: position
        )
    )
}

private func sourceBlobPaths(
    in document: ProjectPackageDocument
) -> Set<String> {
    Set(
        document.manifest?.sourceEntries.lazy
            .map(\.path)
            .filter { $0.hasPrefix(ProjectSourceBlobReference.pathPrefix) }
            ?? []
    )
}

private func documentContainsVertex(
    atZ z: Double,
    document: DesignDocument
) throws -> Bool {
    try assetsContainVertex(atZ: z, assets: document.authoredMeshAssets)
}

private func assetsContainVertex(
    atZ z: Double,
    assets: [GeometrySourceID: AuthoredMeshAsset]
) throws -> Bool {
    try assets.values.contains { asset in
        try asset.source.vertexIDs.contains { vertexID in
            try asset.source.position(of: vertexID).z == z
        }
    }
}

private func withTemporaryDirectory<Result: Sendable>(
    _ body: (URL) async throws -> Result
) async throws -> Result {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "rupa-project-controller-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    do {
        let result = try await body(directory)
        try FileManager.default.removeItem(at: directory)
        return result
    } catch {
        let primaryError = error
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let cleanupError {
            throw ProjectControllerError(
                code: .packageFailed,
                message: "Test failed and temporary cleanup also failed: "
                    + "\(primaryError); \(cleanupError)."
            )
        }
        throw primaryError
    }
}
